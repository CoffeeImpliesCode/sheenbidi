// SPDX-License-Identifier: Apache-2.0
//
//! Deterministic demo of the SheenBidi facade against Unicode's BidiCharacterTest.txt.
//! Checks one published row, script runs, decoders, and caller-supplied allocation.
//! Runtime-loading builds require `--provider` or `SHEENBIDI_PROVIDER`.

const std = @import("std");
const sheenbidi = @import("sheenbidi");

/// Environment variable naming the runtime-loaded shared library.
const provider_variable = "SHEENBIDI_PROVIDER";

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

/// The published row as UTF-32 code points.
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

/// Field 2 of the row.
const expected_paragraph_level: sheenbidi.Level = 0;
/// Field 3 collapsed into runs in visual order.
const expected_runs = [_]sheenbidi.Run{
    .{ .offset = 0, .length = 2, .level = 1 },
    .{ .offset = 2, .length = 1, .level = 0 },
    .{ .offset = 3, .length = 2, .level = 1 },
    .{ .offset = 5, .length = 9, .level = 0 },
};
/// Field 4 of the row.
const expected_order = [_]sheenbidi.CodeUnitIndex{ 1, 0, 2, 4, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13 };

/// Mixed Latin and Hebrew text; Common script joins the Latin run.
const script_text = [_]u32{ 0x0061, 0x0062, 0x0063, 0x0020, 0x05D0, 0x05D1 };

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // Load an explicit provider only in runtime mode.
    if (comptime sheenbidi.runtime_loaded) {
        const provider = try providerRequest(init);
        try sheenbidi.load(.{ .path = provider });
    }

    try w.print("sheenbidi smoke\n", .{});
    try w.print("configuration: {s}\n", .{
        if (sheenbidi.runtime_loaded) "loaded" else "linked",
    });
    try w.print("library version {s}\n", .{sheenbidi.versionString()});
    try w.print(
        "input: BidiCharacterTest.txt line 44, {d} code points, paragraph direction left-to-right\n",
        .{text.len},
    );

    // Source buffers are borrowed and must outlive their objects.
    const source = sheenbidi.Source.fromUtf32(&text);

    var algorithm = try sheenbidi.Algorithm.create(source);
    defer algorithm.deinit();

    var paragraph = try algorithm.createParagraph(0, source.codeUnits(), .{ .explicit = 0 });
    defer paragraph.deinit();

    if (paragraph.baseLevel() != expected_paragraph_level) return error.ParagraphLevelMismatch;
    try w.print("paragraph level {d} (expected {d})\n", .{
        paragraph.baseLevel(),
        expected_paragraph_level,
    });

    var line = try paragraph.createLine(paragraph.offset(), paragraph.length());
    defer line.deinit();

    if (line.length() != text.len) return error.LineLengthMismatch;

    const runs = line.runs();
    if (runs.len != expected_runs.len) return error.RunCountMismatch;

    try w.print("runs, visual order:", .{});
    for (runs, 0..) |run, i| {
        const expected = expected_runs[i];
        if (run.offset != expected.offset or run.length != expected.length or run.level != expected.level) {
            return error.RunMismatch;
        }
        try w.print(" [{d}..{d}] level {d}", .{ run.offset, run.offset + run.length, run.level });
    }
    try w.print("\n", .{});

    const order = try line.visualOrder(init.gpa);
    defer init.gpa.free(order);

    if (order.len != expected_order.len) return error.VisualOrderLengthMismatch;
    try w.print("visual order:", .{});
    for (order, 0..) |index, i| {
        if (index != expected_order[i]) return error.VisualOrderMismatch;
        try w.print(" {d}", .{index});
    }
    try w.print("\n", .{});

    // Hebrew order reverses within the right-to-left run.
    try w.print("first two drawn characters: {d} then {d}\n", .{ order[0], order[1] });
    try w.print("row matches the published expectation\n", .{});

    try scriptRuns(w);
    try decoderWalk(w);
    try customAllocator(w, init.gpa);

    try w.print("every printed answer matched the published expectation\n", .{});
    try w.flush();
}

/// Checks Common-script assignment across mixed-script text.
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

    try w.print("script runs:", .{});
    var observed: usize = 0;
    while (locator.moveNext()) : (observed += 1) {
        if (observed >= expected.len) return error.ScriptRunCountMismatch;
        const run = locator.run();
        try w.print(" [{d}..{d}] {d}", .{ run.offset, run.offset + run.length, run.script });
        const want = expected[observed];
        if (run.offset != want.offset or run.length != want.length or run.script != want.script) {
            return error.ScriptRunMismatch;
        }
    }
    if (observed != expected.len) return error.ScriptRunCountMismatch;
    try w.print("\n", .{});
}

/// Demonstrates UTF-8/UTF-16 code-unit offsets and boundary sentinels.
fn decoderWalk(w: *std.Io.Writer) !void {
    const utf8_units = "a\u{1F600}\u{05D0}";
    const utf16_units = [_]u16{ 0x0061, 0xD83D, 0xDE00, 0x05D0 };

    try w.print("decoders: utf8", .{});
    var index: sheenbidi.CodeUnitIndex = 0;
    var seen: usize = 0;
    while (seen < 3) : (seen += 1) {
        const decoded = sheenbidi.codepointDecodeNextFromUtf8(utf8_units, index);
        if (decoded.codepoint == sheenbidi.codepoint_invalid) return error.DecodeFailed;
        try w.print(" U+{X:0>4}@{d}", .{ decoded.codepoint, index });
        index = decoded.next;
    }
    if (index != utf8_units.len) return error.DecodeLengthMismatch;

    // Past-end decoding returns invalid without advancing (SBCodepoint.c).
    const past_end = sheenbidi.codepointDecodeNextFromUtf8(utf8_units, index);
    if (past_end.codepoint != sheenbidi.codepoint_invalid or past_end.next != index) {
        return error.DecodeOutOfRange;
    }

    // Backward index zero is invalid (SBCodepoint.c).
    const back = sheenbidi.codepointDecodePreviousFromUtf8(utf8_units, utf8_units.len);
    if (back.codepoint != 0x05D0 or back.start != 5) return error.DecodeMismatch;
    const at_zero = sheenbidi.codepointDecodePreviousFromUtf8(utf8_units, 0);
    if (at_zero.codepoint != sheenbidi.codepoint_invalid or at_zero.start != 0) {
        return error.DecodeOutOfRange;
    }

    try w.print("; utf16", .{});
    var index16: sheenbidi.CodeUnitIndex = 0;
    var seen16: usize = 0;
    while (seen16 < 3) : (seen16 += 1) {
        const decoded = sheenbidi.codepointDecodeNextFromUtf16(&utf16_units, index16);
        if (decoded.codepoint == sheenbidi.codepoint_invalid) return error.DecodeFailed;
        try w.print(" U+{X:0>4}@{d}", .{ decoded.codepoint, index16 });
        index16 = decoded.next;
    }
    if (index16 != utf16_units.len) return error.DecodeLengthMismatch;
    const back16 = sheenbidi.codepointDecodePreviousFromUtf16(&utf16_units, utf16_units.len);
    if (back16.codepoint != 0x05D0 or back16.start != 3) return error.DecodeMismatch;
    try w.print("\n", .{});
}

/// Exercises the allocator protocol with tracked allocations.
/// Restore the process default before releasing the allocator.
fn customAllocator(w: *std.Io.Writer, backing: std.mem.Allocator) !void {
    var counters: Counters = .{ .backing = backing };

    var allocator = try sheenbidi.Allocator.create(.{
        .allocateBlock = countersBlock,
        .deallocateBlock = countersDeallocate,
        // Optional reallocate, scratch, and finalize callbacks remain null (SBAllocator.h).
    }, &counters);
    defer allocator.deinit();

    const previous = sheenbidi.c.SBAllocatorGetDefault();
    sheenbidi.c.SBAllocatorSetDefault(allocator.ref);
    defer sheenbidi.c.SBAllocatorSetDefault(previous);

    {
        var scoped = try sheenbidi.Algorithm.create(sheenbidi.Source.fromUtf32(&text));
        scoped.deinit();
    }

    if (counters.allocated == 0 or counters.freed != counters.allocated) {
        return error.AllocatorNotUsed;
    }
    try w.print(
        "custom allocator: {d} blocks in, {d} blocks out, {d} live\n",
        .{ counters.allocated, counters.freed, counters.liveCount() },
    );
}

/// Limits the number of blocks tracked at once.
const max_live_blocks = 64;

/// Tracks callback allocations using the caller's backing allocator.
const Counters = struct {
    backing: std.mem.Allocator,
    allocated: usize = 0,
    freed: usize = 0,
    live: [max_live_blocks]struct { address: usize, bytes: usize } =
        @splat(.{ .address = 0, .bytes = 0 }),

    /// Returns the current live block count.
    fn liveCount(self: *const Counters) usize {
        var live: usize = 0;
        for (self.live) |slot| {
            if (slot.bytes != 0) live += 1;
        }
        return live;
    }
};

/// C allocation callback; blocks need pointer alignment and null signals failure.
fn countersBlock(size: sheenbidi.CodeUnitIndex, info: ?*anyopaque) callconv(.c) ?*anyopaque {
    const counters: *Counters = @ptrCast(@alignCast(info orelse return null));
    // Zero-sized blocks cannot be tracked.
    if (size == 0) return null;
    for (&counters.live) |*slot| {
        if (slot.bytes != 0) continue;
        const bytes = counters.backing.alignedAlloc(u8, .fromByteUnits(@alignOf(usize)), size) catch
            return null;
        slot.* = .{ .address = @intFromPtr(bytes.ptr), .bytes = bytes.len };
        counters.allocated += 1;
        return bytes.ptr;
    }
    return null;
}

/// `SBAllocatorDeallocateBlockFunc`, `Headers/SheenBidi/SBAllocator.h:60`.
fn countersDeallocate(pointer: ?*anyopaque, info: ?*anyopaque) callconv(.c) void {
    const counters: *Counters = @ptrCast(@alignCast(info orelse return));
    const address = @intFromPtr(pointer);
    for (&counters.live) |*slot| {
        if (slot.bytes == 0 or slot.address != address) continue;
        const block: [*]align(@alignOf(usize)) u8 = @ptrFromInt(slot.address);
        const size: usize = @intCast(slot.bytes);
        slot.* = .{ .address = 0, .bytes = 0 };
        counters.freed += 1;
        counters.backing.free(block[0..size]);
        return;
    }
}

/// Selects a provider path from the CLI or environment.
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

/// Reports missing runtime provider configuration.
fn noProvider() ConfigurationError {
    std.debug.print(
        "smoke: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export {s} with a shared object exporting the fifty-one entry points " ++
            "of the stable SheenBidi surface. Nothing is loaded by default and " ++
            "no other file is tried.\n",
        .{provider_variable},
    );
    return error.NoProviderConfigured;
}
