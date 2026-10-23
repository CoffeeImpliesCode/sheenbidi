// SPDX-License-Identifier: Apache-2.0
//
//! Consumes the package API and checks bidi order, mirroring, script runs, and allocator ownership.
//! In runtime-loading mode, provide `--provider <path>` or set `SHEENBIDI_PROVIDER`.

const std = @import("std");
const sheenbidi = @import("sheenbidi");

/// Provider variable used by runtime-loading builds.
const provider_variable = "SHEENBIDI_PROVIDER";

const ConfigurationError = error{NoProviderConfigured};

/// BidiCharacterTest.txt line 45, field 0.
const text = [_]u32{
    0x05D0, // HEBREW LETTER ALEF
    0x05D1, // HEBREW LETTER BET
    0x0028, // LEFT PARENTHESIS
    0x05D2, // HEBREW LETTER GIMEL
    0x05D3, // HEBREW LETTER DALET
    0x005B, // LEFT SQUARE BRACKET
    0x0026, // AMPERSAND
    0x0065, // LATIN SMALL LETTER E
    0x0066, // LATIN SMALL LETTER F
    0x005D, // RIGHT SQUARE BRACKET
    0x002E, // FULL STOP
    0x0029, // RIGHT PARENTHESIS
    0x0067, // LATIN SMALL LETTER G
    0x0068, // LATIN SMALL LETTER H
};

const paragraph_base: sheenbidi.BaseLevel = .{ .explicit = 1 };

const expected_paragraph_level: sheenbidi.Level = 1;

const expected_runs = [_]sheenbidi.Run{
    .{ .offset = 12, .length = 2, .level = 2 },
    .{ .offset = 9, .length = 3, .level = 1 },
    .{ .offset = 7, .length = 2, .level = 2 },
    .{ .offset = 0, .length = 7, .level = 1 },
};

const expected_order = [_]sheenbidi.CodeUnitIndex{
    12, 13, 11, 10, 9, 7, 8, 6, 5, 4, 3, 2, 1, 0,
};

/// Expected mirrored pairs in visual traversal order.
const expected_mirrors = [_]struct {
    index: sheenbidi.CodeUnitIndex,
    codepoint: sheenbidi.Codepoint,
    mirrored: sheenbidi.Codepoint,
}{
    .{ .index = 9, .codepoint = 0x005D, .mirrored = 0x005B }, // ] -> [
    .{ .index = 11, .codepoint = 0x0029, .mirrored = 0x0028 }, // ) -> (
    .{ .index = 2, .codepoint = 0x0028, .mirrored = 0x0029 }, // ( -> )
    .{ .index = 5, .codepoint = 0x005B, .mirrored = 0x005D }, // [ -> ]
};

/// Expected script runs for font selection.
/// Common characters inherit the surrounding script, so the space stays in the Latin run.
const script_text = [_]u32{ 0x0061, 0x0062, 0x0063, 0x0020, 0x05D0, 0x05D1 };

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    if (comptime sheenbidi.runtime_loaded) {
        const provider = try providerRequest(init);
        try sheenbidi.load(.{ .path = provider });
    }

    // The source remains borrowed until all derived objects are deinitialized.
    const source = sheenbidi.Source.fromUtf32(&text);

    var algorithm = try sheenbidi.Algorithm.create(source);
    defer algorithm.deinit();

    var paragraph = try algorithm.createParagraph(0, source.codeUnits(), paragraph_base);
    defer paragraph.deinit();

    try w.print("sheenbidi consumer, version {s}\n", .{sheenbidi.versionString()});
    try w.print("configuration: {s}\n", .{
        if (sheenbidi.runtime_loaded) "loaded" else "linked",
    });
    try w.print("{d} code points, explicit right-to-left paragraph\n", .{text.len});

    const base_level = paragraph.baseLevel();
    if (base_level != expected_paragraph_level) return error.ParagraphLevelMismatch;
    try w.print("paragraph level {d}\n", .{base_level});

    var line = try paragraph.createLine(paragraph.offset(), paragraph.length());
    defer line.deinit();

    const runs = line.runs();
    if (runs.len != expected_runs.len) return error.RunCountMismatch;
    try w.print("runs in visual order:\n", .{});
    for (runs, 0..) |run, i| {
        const expected = expected_runs[i];
        if (run.offset != expected.offset or run.length != expected.length or run.level != expected.level) {
            return error.RunMismatch;
        }
        try w.print("  code units {d}..{d} at level {d}\n", .{
            run.offset,
            run.offset + run.length,
            run.level,
        });
    }

    const order = try line.visualOrder(init.gpa);
    defer init.gpa.free(order);

    if (order.len != expected_order.len) return error.VisualOrderLengthMismatch;
    try w.print("visual order:", .{});
    for (order, 0..) |index, i| {
        if (index != expected_order[i]) return error.VisualOrderMismatch;
        try w.print(" {d}", .{index});
    }
    try w.print("\n", .{});

    // Visual order reverses the Hebrew endpoints while preserving the Latin runs.
    try w.print("drawn first {d} (g), drawn last {d} (alef)\n", .{ order[0], order[order.len - 1] });
    if (order[0] != 12 or order[order.len - 1] != 0) return error.RunOrderMismatch;

    try mirrorWalk(w, line);
    try scriptRuns(w);
    try owningAllocator(w, init.gpa);

    try w.print("all published values for row 45 reproduced\n", .{});
    try w.flush();
}

/// Walks mirrored characters in the same visual order a renderer uses.
fn mirrorWalk(w: *std.Io.Writer, line: sheenbidi.Line) !void {
    var mirror_locator = try sheenbidi.MirrorLocator.create();
    defer mirror_locator.deinit();
    mirror_locator.loadLine(line);

    try w.print("mirrors in right-to-left runs:\n", .{});
    for (expected_mirrors) |expected| {
        if (!mirror_locator.moveNext()) return error.MissingMirror;
        const found = mirror_locator.mirror();
        if (found.index != expected.index or
            found.codepoint != expected.codepoint or
            found.mirrored != expected.mirrored)
        {
            return error.MirrorMismatch;
        }
        try w.print("  index {d}: U+{X:0>4} draws as U+{X:0>4}\n", .{
            found.index,
            found.codepoint,
            found.mirrored,
        });
    }
    if (mirror_locator.moveNext()) return error.ExtraMirror;
}

/// Checks script runs and their Unicode and OpenType tags.
fn scriptRuns(w: *std.Io.Writer) !void {
    var locator = try sheenbidi.ScriptLocator.create();
    defer locator.deinit();
    locator.load(sheenbidi.Source.fromUtf32(&script_text));

    const latin: sheenbidi.Script = @intCast(sheenbidi.c.SBScriptLATN);
    const hebrew: sheenbidi.Script = @intCast(sheenbidi.c.SBScriptHEBR);
    const expected = [_]sheenbidi.ScriptRun{
        .{ .offset = 0, .length = 4, .script = latin },
        .{ .offset = 4, .length = 2, .script = hebrew },
    };

    try w.print("script runs:\n", .{});
    var observed: usize = 0;
    while (locator.moveNext()) : (observed += 1) {
        if (observed >= expected.len) return error.ScriptRunCountMismatch;
        const run = locator.run();
        const want = expected[observed];
        if (run.offset != want.offset or run.length != want.length or run.script != want.script) {
            return error.ScriptRunMismatch;
        }
        try w.print("  code units {d}..{d}: unicode {X:0>8} opentype {X:0>8}\n", .{
            run.offset,
            run.offset + run.length,
            sheenbidi.scriptUnicodeTag(run.script),
            sheenbidi.scriptOpenTypeTag(run.script),
        });
    }
    if (observed != expected.len) return error.ScriptRunCountMismatch;

    if (sheenbidi.scriptUnicodeTag(hebrew) != 0x48656272) return error.ScriptTagMismatch;
    if (sheenbidi.scriptOpenTypeTag(hebrew) != 0x68656272) return error.ScriptTagMismatch;
    if (sheenbidi.scriptUnicodeTag(latin) != 0x4C61746E) return error.ScriptTagMismatch;
    if (sheenbidi.scriptOpenTypeTag(latin) != 0x6C61746E) return error.ScriptTagMismatch;
}

/// Installs a consumer-owned allocator while constructing and releasing an object.
/// The ledger confirms all blocks return before the previous default is restored.
fn owningAllocator(w: *std.Io.Writer, backing: std.mem.Allocator) !void {
    var ledger: Ledger = .{ .backing = backing };

    var allocator = try sheenbidi.Allocator.create(.{
        .allocateBlock = ledgerBlock,
        .deallocateBlock = ledgerFree,
    }, &ledger);
    defer allocator.deinit();

    const previous = sheenbidi.c.SBAllocatorGetDefault();
    sheenbidi.c.SBAllocatorSetDefault(allocator.ref);
    defer sheenbidi.c.SBAllocatorSetDefault(previous);

    {
        // A second algorithm object under the consumer's allocator, so the
        // counts are about a real object and not about an empty scope.
        var scoped = try sheenbidi.Algorithm.create(sheenbidi.Source.fromUtf32(&script_text));
        scoped.deinit();
    }

    if (ledger.taken == 0 or ledger.returned != ledger.taken or ledger.live() != 0) {
        return error.AllocatorNotHonoured;
    }
    try w.print(
        "own allocator: {d} blocks taken, {d} returned, {d} still live\n",
        .{ ledger.taken, ledger.returned, ledger.live() },
    );
}

const max_blocks = 64;

/// Tracks blocks so release callbacks can free the correct backing slices.
const Ledger = struct {
    backing: std.mem.Allocator,
    taken: usize = 0,
    returned: usize = 0,
    blocks: [max_blocks]struct { address: usize, bytes: usize } =
        @splat(.{ .address = 0, .bytes = 0 }),

    fn live(self: *const Ledger) usize {
        var count: usize = 0;
        for (self.blocks) |slot| {
            if (slot.bytes != 0) count += 1;
        }
        return count;
    }
};

/// Allocates pointer-aligned blocks and returns null when allocation fails.
fn ledgerBlock(size: sheenbidi.CodeUnitIndex, info: ?*anyopaque) callconv(.c) ?*anyopaque {
    const ledger: *Ledger = @ptrCast(@alignCast(info orelse return null));
    if (size == 0) return null;
    for (&ledger.blocks) |*slot| {
        if (slot.bytes != 0) continue;
        const block = ledger.backing.alignedAlloc(u8, .fromByteUnits(@alignOf(usize)), size) catch return null;
        slot.* = .{ .address = @intFromPtr(block.ptr), .bytes = block.len };
        ledger.taken += 1;
        return block.ptr;
    }
    return null;
}

/// `SBAllocatorDeallocateBlockFunc`, declared in `SBAllocator.h`.
fn ledgerFree(pointer: ?*anyopaque, info: ?*anyopaque) callconv(.c) void {
    const ledger: *Ledger = @ptrCast(@alignCast(info orelse return));
    const address = @intFromPtr(pointer);
    for (&ledger.blocks) |*slot| {
        if (slot.bytes == 0 or slot.address != address) continue;
        const block: [*]align(@alignOf(usize)) u8 = @ptrFromInt(slot.address);
        const size: usize = @intCast(slot.bytes);
        slot.* = .{ .address = 0, .bytes = 0 };
        ledger.returned += 1;
        ledger.backing.free(block[0..size]);
        return;
    }
}

/// Resolves the provider path from arguments or the environment.
fn providerRequest(init: std.process.Init) ConfigurationError![]const u8 {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch
        return noProvider();
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--provider")) {
            if (index + 1 >= args.len) return noProvider();
            return args[index + 1];
        }
    }
    return init.environ_map.get(provider_variable) orelse
        return noProvider();
}

fn noProvider() ConfigurationError {
    std.debug.print(
        "sheenbidi consumer: this is a runtime-loading build. Pass " ++
            "--provider <path>, or export {s} with a shared object exporting " ++
            "the fifty-one entry points of the stable SheenBidi surface. Nothing " ++
            "is loaded by default and no other file is tried.\n",
        .{provider_variable},
    );
    return error.NoProviderConfigured;
}
