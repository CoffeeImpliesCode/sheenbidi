// SPDX-License-Identifier: Apache-2.0
//
//! Reusable process-wide loader for generated C dispatches.
//! Successful providers stay loaded; failed attempts publish nothing and may be retried explicitly.
//! Calls before readiness panic; unsupported targets return `UnsupportedTarget`.

const std = @import("std");
const builtin = @import("builtin");

/// A file path or platform loader name; neither form falls back to the other.
pub const LoadSource = union(enum) {
    /// An absolute file path.
    path: []const u8,
    /// A separator-free basename searched by the platform loader.
    system: []const u8,
};

/// Errors returned while opening, resolving, or validating a provider.
pub const LoadError = error{
    /// The path or system name is empty.
    EmptySource,
    /// The request exceeds `max_source_len`.
    SourceTooLong,
    /// The path is not absolute or the system name contains a separator or NUL.
    InvalidSource,
    /// The target has no dynamic library loader.
    UnsupportedTarget,
    /// The platform loader could not open the requested provider.
    OpenFailed,
    /// A required translated symbol is not exported.
    MissingSymbol,
    /// The provider failed the library-specific validation callback.
    ValidationFailed,
    /// A different source is already loaded or in flight.
    ProviderMismatch,
    /// The attempt called `load` again on its own thread.
    ReentrantLoad,
};

/// Maximum request length, in bytes.
pub const max_source_len = 32768;

/// Fixed-size copy of the source request, retained for process lifetime.
const SourceRecord = struct {
    tag: enum(u8) { none = 0, path, system } = .none,
    len: u32 = 0,
    bytes: [max_source_len]u8 = undefined,

    /// Stores a validated request under the loader lock.
    fn set(self: *SourceRecord, request: LoadSource) void {
        const text = switch (request) {
            .path => |p| p,
            .system => |s| s,
        };
        @memcpy(self.bytes[0..text.len], text);
        self.len = @intCast(text.len);
        self.tag = switch (request) {
            .path => .path,
            .system => .system,
        };
    }

    /// Returns the remembered request, if any.
    pub fn source(self: *const SourceRecord) ?LoadSource {
        const text = self.bytes[0..self.len];
        return switch (self.tag) {
            .none => null,
            .path => .{ .path = text },
            .system => .{ .system = text },
        };
    }
};

/// Compares source kind and bytes without path normalization.
pub fn eqlSource(a: LoadSource, b: LoadSource) bool {
    return switch (a) {
        .path => |pa| switch (b) {
            .path => |pb| std.mem.eql(u8, pa, pb),
            .system => false,
        },
        .system => |sa| switch (b) {
            .system => |sb| std.mem.eql(u8, sa, sb),
            .path => false,
        },
    };
}

fn validateSource(source: LoadSource) LoadError!void {
    const text = switch (source) {
        .path => |p| p,
        .system => |s| s,
    };
    if (text.len == 0) return error.EmptySource;
    if (text.len > max_source_len) return error.SourceTooLong;
    if (std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidSource;
    switch (source) {
        .path => {
            const absolute = if (builtin.target.os.tag == .windows)
                switch (std.fs.path.getWin32PathType(u8, text)) {
                    .drive_absolute, .unc_absolute, .local_device, .root_local_device => true,
                    .relative, .rooted, .drive_relative => false,
                }
            else
                std.fs.path.isAbsolutePosix(text);
            if (!absolute) return error.InvalidSource;
        },
        .system => {
            for (text) |byte| {
                if (std.fs.path.isSep(byte)) return error.InvalidSource;
                if (builtin.target.os.tag == .windows and byte == ':') return error.InvalidSource;
            }
        },
    }
}

/// State of a configured loader's dispatch table.
pub const Phase = enum(u8) {
    /// No active or successful provider.
    not_loaded = 0,
    /// A thread is resolving symbols.
    loading = 1,
    /// The table is published.
    ready = 2,
};

/// Publishes table readiness with release/acquire ordering.
pub const Ready = struct {
    phase: std.atomic.Value(u8) = .init(@backingInt(Phase.not_loaded)),

    /// Whether a provider has been published.
    pub fn isReady(self: *const Ready) bool {
        return self.phase.load(.acquire) == @backingInt(Phase.ready);
    }

    /// Current table state.
    pub fn state(self: *const Ready) Phase {
        return @fromBackingInt(@intCast(self.phase.load(.acquire)));
    }

    /// Stores a table state with release ordering.
    pub fn set(self: *Ready, value: Phase) void {
        self.phase.store(@backingInt(value), .release);
    }
};

/// Kind of required exported symbol.
pub const SymbolKind = enum {
    /// Function pointer.
    function,
    /// Address of exported data.
    data,
};

/// One required export and its kind.
pub const Symbol = struct {
    /// Exported name from the translated header.
    name: [:0]const u8,
    /// Value stored in the table.
    kind: SymbolKind,
};

/// Panics in every optimization mode when a routed call precedes a successful load.
/// The panic identifies the library and symbol.
pub fn panicNotReady(library: []const u8, comptime symbol: []const u8) noreturn {
    std.debug.panic(
        "{s}: {s} was called before this module was loaded; call " ++
            "load({{ .path = \"...\" }}) or load({{ .system = \"...\" }}) first",
        .{ library, symbol },
    );
}

/// Whether the target has a dynamic library loader.
pub const supported_target: bool = switch (builtin.target.os.tag) {
    .wasi, .emscripten, .freestanding => false,
    else => true,
};

/// Retains one successful provider; different requests return `ProviderMismatch`.
/// Failed attempts may be retried explicitly; constructors must not wait on another thread calling `load`.
pub fn Loader(comptime Config: type) type {
    return struct {
        const LoaderType = @This();

        /// The dispatch table type.
        pub const table_type = Config.table;

        /// Current or draining attempt.
        attempt: ?Attempt = null,

        /// Source request retained for the active or successful provider.
        request: SourceRecord = .{},

        /// Resolves a provider and publishes its dispatch table.
        /// Identical in-flight requests share the result.
        pub fn load(self: *LoaderType, source: LoadSource) LoadError!void {
            try validateSource(source);
            // Fast path for an already loaded provider.

            if (Config.ready().isReady()) return self.accept(source);
            Config.sync.lock();
            while (true) {
                switch (Config.ready().state()) {
                    .ready => {
                        Config.sync.unlock();
                        return self.accept(source);
                    },
                    .loading => {
                        const attempt = &self.attempt.?;
                        if (attempt.owner == Config.sync.threadSelf()) {
                            Config.sync.unlock();
                            return error.ReentrantLoad;
                        }
                        if (!eqlSource(self.request.source().?, source)) {
                            Config.sync.unlock();
                            return error.ProviderMismatch;
                        }
                        // Wait for the matching in-flight request.
                        attempt.waiters += 1;
                        while (Config.ready().state() == .loading) Config.sync.wait();
                        const result = attempt.result;
                        attempt.waiters -= 1;
                        // Keep the attempt until all waiters consume its result.
                        Config.sync.broadcast();
                        Config.sync.unlock();
                        return result;
                    },
                    .not_loaded => {
                        // Wait for waiters to drain before allowing a retry.
                        if (self.attempt != null) {
                            Config.sync.wait();
                            continue;
                        }
                        break;
                    },
                }
            }

            self.request.set(source);
            self.attempt = .{ .owner = Config.sync.threadSelf() };
            Config.ready().set(.loading);
            Config.sync.unlock();

            // Open without the lock; other callers wait on the attempt.
            const outcome = runAttempt(self.request.source().?);
            const succeeded = if (outcome) |_| true else |_| false;

            Config.sync.lock();
            self.attempt.?.result = outcome;
            Config.ready().set(if (succeeded) .ready else .not_loaded);
            // Wake every caller attached to this attempt.
            Config.sync.broadcast();
            // Drain waiters before clearing the attempt record.
            while (self.attempt.?.waiters > 0) Config.sync.wait();
            self.attempt = null;
            // Wake callers waiting to retry.
            Config.sync.broadcast();
            Config.sync.unlock();

            return outcome;
        }

        /// Returns the successful source, or null before a provider is loaded.
        pub fn loadedSource(self: *const LoaderType) ?LoadSource {
            if (!Config.ready().isReady()) return null;
            return self.request.source();
        }

        /// The request already in use, checked against a new one.
        fn accept(self: *const LoaderType, source: LoadSource) LoadError!void {
            const published = self.request.source() orelse unreachable;
            if (eqlSource(published, source)) return;
            return error.ProviderMismatch;
        }

        /// Opens, resolves, and validates a provider without publishing it.
        fn runAttempt(source: LoadSource) LoadError!void {
            const handle = platform.open(source) catch |err| return err;

            var retain = false;
            defer if (!retain) platform.close(handle);

            if (@hasDecl(Config, "optional_symbols")) {
                inline for (Config.optional_symbols, 0..) |_, index| {
                    Config.assignMissing(index, Config.tablePtr());
                }
            }

            inline for (Config.symbols, 0..) |symbol, index| {
                const address = platform.lookup(handle, symbol.name) orelse
                    return error.MissingSymbol;
                Config.assign(index, Config.tablePtr(), address);
            }

            if (@hasDecl(Config, "optional_symbols")) {
                inline for (Config.optional_symbols, 0..) |symbol, index| {
                    if (platform.lookup(handle, symbol.name)) |address| {
                        Config.assignOptional(index, Config.tablePtr(), address);
                    }
                }
            }

            if (@hasDecl(Config, "validate")) {
                if (Config.validate(Config.tablePtr())) |refusal| {
                    std.debug.print("{s}: refusing this provider: {s}\n", .{
                        Config.library_name,
                        refusal,
                    });
                    return error.ValidationFailed;
                }
            }

            // Keep the handle while the dispatch references its symbols.
            retain = true;
        }
    };
}

// Platform dynamic-loader implementations.

/// One active or draining load attempt.
const Attempt = struct {
    /// Thread running this attempt, for reentrancy detection.
    owner: u64,
    /// Written before waiters wake and read only afterward.
    result: LoadError!void = error.OpenFailed,
    /// Number of waiters that still need this attempt's result.
    waiters: usize = 0,
};

/// Maximum UTF-16 path length accepted by the Windows loader.
const windows_path_units = 32768;

const platform = if (builtin.target.os.tag == .windows)
    Windows
else if (supported_target)
    Unix
else
    NoLoader;

/// Loader stub for targets without dynamic-loading support.
const NoLoader = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget };

    fn open(source: LoadSource) OpenError!*anyopaque {
        _ = source;
        return error.UnsupportedTarget;
    }
    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        _ = handle;
        _ = name;
        return null;
    }
    fn close(handle: *anyopaque) void {
        _ = handle;
    }
};

/// Unix dynamic-loader backend.
const Unix = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget };

    fn open(source: LoadSource) OpenError!*anyopaque {
        const text = switch (source) {
            .path => |p| p,
            .system => |s| s,
        };
        var buffer: [max_source_len + 1]u8 = undefined;
        @memcpy(buffer[0..text.len], text);
        buffer[text.len] = 0;
        // Resolve dependencies eagerly and keep provider symbols local.
        return std.c.dlopen(
            // `dlopen` requires a sentinel-terminated name.
            buffer[0..text.len :0].ptr,
            .{ .NOW = true, .GLOBAL = false },
        ) orelse error.OpenFailed;
    }

    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        return std.c.dlsym(handle, name.ptr);
    }

    fn close(handle: *anyopaque) void {
        _ = std.c.dlclose(handle);
    }
};

/// Windows API declarations used by this backend.
const kernel32 = struct {
    extern "kernel32" fn LoadLibraryExW(
        file_name: [*:0]const u16,
        file: ?*anyopaque,
        flags: u32,
    ) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn GetProcAddress(module: *anyopaque, name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn FreeLibrary(module: *anyopaque) callconv(.winapi) i32;
};

/// Windows dynamic-loader backend.
const Windows = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget, SourceTooLong };

    /// Search standard directories without adding the current directory.
    const load_library_search_default_dirs: u32 = 0x0000_1000;
    const load_library_search_dll_load_dir: u32 = 0x0000_0100;

    fn open(source: LoadSource) OpenError!*anyopaque {
        const text = switch (source) {
            .path => |p| p,
            .system => |s| s,
        };
        if (text.len > windows_path_units) return error.SourceTooLong;
        var buffer: [windows_path_units + 1]u16 = undefined;
        const units = std.unicode.utf8ToUtf16Le(buffer[0..text.len], text) catch
            return error.OpenFailed;
        buffer[units] = 0;
        return kernel32.LoadLibraryExW(
            buffer[0..units :0],
            null,
            load_library_search_default_dirs | switch (source) {
                .path => load_library_search_dll_load_dir,
                .system => @as(u32, 0),
            },
        ) orelse error.OpenFailed;
    }

    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        return kernel32.GetProcAddress(handle, name.ptr);
    }

    fn close(handle: *anyopaque) void {
        _ = kernel32.FreeLibrary(handle);
    }
};
