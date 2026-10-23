// SPDX-License-Identifier: Apache-2.0
//
//! SheenBidi's runtime-loader descriptor.
//! It binds synchronization symbols and validates the provider's stable ABI.
const rt = @import("rt");

/// Namespaced synchronization callbacks for the runtime loader.
pub const Sync = struct {
    extern fn sheenbidi_rt_lock() void;
    extern fn sheenbidi_rt_unlock() void;
    extern fn sheenbidi_rt_wait() void;
    extern fn sheenbidi_rt_broadcast() void;
    // `unsigned long long`. Declared as u64, which is the same type in every
    // ABI this SDK targets: 64-bit on x86_64, aarch64, riscv64 and wasm32.
    extern fn sheenbidi_rt_thread_self() u64;

    pub fn lock() void {
        sheenbidi_rt_lock();
    }
    pub fn unlock() void {
        sheenbidi_rt_unlock();
    }
    pub fn wait() void {
        sheenbidi_rt_wait();
    }
    pub fn broadcast() void {
        sheenbidi_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return sheenbidi_rt_thread_self();
    }
};

/// Maximum version string length accepted during provider validation.
const max_version_len = 128;

/// Binds a generated dispatch table to SheenBidi's loader checks.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Name included in loader errors.
        pub const library_name = "sheenbidi";

        /// Table and exports emitted from the translated header.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// The project's namespaced synchronization binding.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        /// Assigns a resolved optional symbol or clears its absent table field.
        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// Validates a complete table before the loader publishes it.
        pub fn validate(dst: *const table) ?[]const u8 {
            return validateVersion(dst) orelse
                validateCodePointTables(dst) orelse
                validateSequenceLayout(dst);
        }

        /// Rejects empty or unterminated provider version strings.
        fn validateVersion(dst: *const table) ?[]const u8 {
            const version: [*c]const u8 = dst.SBVersionGetString();
            var length: usize = 0;
            while (length < max_version_len) : (length += 1) {
                if (version[length] == 0) break;
            }
            if (length == 0) {
                return "SBVersionGetString() answered with an empty string, so this " ++
                    "provider is not the library this header describes";
            }
            if (length == max_version_len) {
                return "SBVersionGetString() answered with no terminator within " ++
                    "128 bytes, so this provider is not the library this header " ++
                    "describes";
            }
            return null;
        }

        /// Checks stable codepoint answers that also expose scalar-width mismatches.
        fn validateCodePointTables(dst: *const table) ?[]const u8 {
            const latin_a: dispatch.SBCodepoint = 0x0041;
            const hebrew_alef: dispatch.SBCodepoint = 0x05D0;

            const type_a: dispatch.SBBidiType = @intCast(dispatch.SBBidiTypeL);
            if (dst.SBCodepointGetBidiType(latin_a) != type_a) {
                return "SBCodepointGetBidiType(U+0041) did not answer SBBidiTypeL, " ++
                    "so this provider is not the library this header describes";
            }
            const script_alef: dispatch.SBScript = @intCast(dispatch.SBScriptHEBR);
            if (dst.SBCodepointGetScript(hebrew_alef) != script_alef) {
                return "SBCodepointGetScript(U+05D0) did not answer SBScriptHEBR, " ++
                    "so this provider is not the library this header describes";
            }
            return null;
        }

        /// Checks that the provider accepts this build's sequence layout.
        fn validateSequenceLayout(dst: *const table) ?[]const u8 {
            var units = [_]u8{ 'a', 'b' };
            const sequence: dispatch.SBCodepointSequence = .{
                .stringEncoding = @intCast(dispatch.SBStringEncodingUTF8),
                .stringBuffer = &units,
                .stringLength = units.len,
            };
            const algorithm = dst.SBAlgorithmCreate(&sequence);
            if (algorithm == null) {
                return "SBAlgorithmCreate() returned NULL for a two-code-unit " ++
                    "sequence, so this provider is not the library this header " ++
                    "describes";
            }
            dst.SBAlgorithmRelease(algorithm);
            return null;
        }
    };
}
