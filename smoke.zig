// SPDX-License-Identifier: Apache-2.0
//
//! A runnable, deterministic demonstration of the facade.
//!
//! The input is a published conformance row, not a string invented here:
//! `Tools/Unicode/BidiCharacterTest.txt` line 44, which is the worked example
//! from UAX #9 itself:
//!
//!   <HEBREW ALEF> <HEBREW BET> ( <HEBREW GIMEL> <HEBREW DALET> [ & e f ] . ) g h
//!
//! The expected paragraph level, the expected runs and the expected visual
//! order are the ones Unicode publishes for that row. The program asserts all
//! of them and prints them, so a run of `zig build smoke` is both a
//! demonstration and a check: an exit status of zero means SheenBidi agreed
//! with the published answer on every character.
//!
//! It then exercises three parts of the surface that row does not reach — the
//! script locator, the borrowed decoders and a caller-supplied allocator —
//! against answers read out of Unicode's own data files, so what is printed is
//! what the Unicode Consortium publishes rather than what this library just
//! said about itself.
//!
//! ## Naming a provider
//!
//! In a runtime-loading build nothing here is callable until a provider is
//! named, and the provider is never guessed: pass `--provider <path>`, or
//! export `SHEENBIDI_PROVIDER`. A build that was told neither stops with a
//! message saying which of the two was missing. In the ordinary linked build
//! both are ignored and no provider is involved at all.
//!
//! Nothing here depends on timing, on a locale or on an environment variable's
//! value, so the output is the same on every host and a change in it is a change
//! in behaviour. The version line is printed rather than asserted: which
//! upstream release this binary was linked against, or loaded, belongs to the
//! provenance gate.

const std = @import("std");
const sheenbidi = @import("sheenbidi");

/// A shared object exporting the fifty-one entry points of the stable
/// SheenBidi surface, named by the environment in a runtime-loading build.
const provider_variable = "SHEENBIDI_PROVIDER";

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

/// The row, as code points. Kept in UTF-32 so that a code unit index in the
/// output is also a character index and can be read against the fixture.
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
/// Field 3 of the row, collapsed into the runs the line is made of. The runs
/// are listed in visual order, which is the order `SBLineGetRunsPtr` returns
/// them in.
const expected_runs = [_]sheenbidi.Run{
    .{ .offset = 0, .length = 2, .level = 1 },
    .{ .offset = 2, .length = 1, .level = 0 },
    .{ .offset = 3, .length = 2, .level = 1 },
    .{ .offset = 5, .length = 9, .level = 0 },
};
/// Field 4 of the row.
const expected_order = [_]sheenbidi.CodeUnitIndex{ 1, 0, 2, 4, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13 };

/// LATIN SMALL LETTER A, B, C, then a space, then HEBREW LETTER ALEF and BET:
/// two scripts, with a Common space that joins the run it sits in. The expected
/// runs are what `Tools/Unicode/Scripts.txt` gives for these code points —
/// `0061..007A ; Latn`, `0020 ; Zyyy`, `05D0..05D5 ; Hebr` — under the
/// locator's rule that a Common code point takes the script of the text it is
/// enclosed by, which here is Latin.
const script_text = [_]u32{ 0x0061, 0x0062, 0x0063, 0x0020, 0x05D0, 0x05D1 };

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // In a runtime-loading build nothing below can run until a provider is
    // loaded, and the load is the one explicit step the contract asks for. In a
    // linked build this is a no-op at comptime and the module is already
    // usable.
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

    // The code units are borrowed: `text` is a local array and every object
    // below reads through it, so it has to outlive all of them.
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

    // The two Hebrew letters head the line, and the pair comes out in the
    // opposite order; the Latin letters and the brackets keep their places
    // because the paragraph resolves left-to-right.
    try w.print("first two drawn characters: {d} then {d}\n", .{ order[0], order[1] });
    try w.print("row matches the published expectation\n", .{});

    try scriptRuns(w);
    try decoderWalk(w);
    try customAllocator(w, init.gpa);

    try w.print("every printed answer matched the published expectation\n", .{});
    try w.flush();
}

/// `SBScriptLocator` over `script_text`.
///
/// The locator is a second, independent reader of the same kind of text: it
/// copies the `SBCodepointSequence` and retains nothing, so the code units are
/// still the caller's obligation while it is loaded. What is being checked is
/// the Common-script rule: U+0020 is `Zyyy` in `Scripts.txt`, and the run it
/// produces is four code units long rather than three because a Common code
/// point takes the script of the text it is enclosed by.
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

/// The four direct decoders, over the same three code points in UTF-8 and
/// UTF-16.
///
/// These are the raw-buffer entry points rather than the sequence ones, and the
/// point of showing them is the index space: one text, two encodings, the same
/// code points at different code unit offsets. `a` is one code unit everywhere,
/// GRINNING FACE is four in UTF-8 and two in UTF-16, and HEBREW LETTER ALEF is
/// two and one.
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

    // Past the last code point the decoder reports the invalid sentinel and
    // leaves the index where it was (`Source/API/SBCodepoint.c:245`).
    const past_end = sheenbidi.codepointDecodeNextFromUtf8(utf8_units, index);
    if (past_end.codepoint != sheenbidi.codepoint_invalid or past_end.next != index) {
        return error.DecodeOutOfRange;
    }

    // The same walk backwards: the Hebrew letter is the code point before the
    // end, and asking from index 0 is the invalid case with the index unchanged
    // (`Source/API/SBCodepoint.c:283` rejects it by a wrapping subtraction).
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

/// A caller-supplied allocator, installed for the length of one object.
///
/// This is the `SBAllocatorProtocol` contract in miniature: the two members
/// SheenBidi calls unconditionally must be set, the four it treats as optional
/// may be left null, and the allocator object has to exist before the object
/// that uses it. The counters are the assertion — the object below must come
/// from `allocateBlock` and go back through `deallocateBlock`, and the live
/// count must be back to zero.
///
/// The allocator is installed with the raw `c.SBAllocatorSetDefault`, because a
/// process-wide default has no owner this module can give it. The restore is a
/// `defer` registered *after* the allocator's own, so it runs first: that
/// ordering is the retention rule under [Allocations], and this program obeys it
/// rather than asserting it, because getting it wrong frees the object out from
/// under itself.
fn customAllocator(w: *std.Io.Writer, backing: std.mem.Allocator) !void {
    var counters: Counters = .{ .backing = backing };

    var allocator = try sheenbidi.Allocator.create(.{
        .allocateBlock = countersBlock,
        .deallocateBlock = countersDeallocate,
        // `reallocateBlock`, `allocateScratch`, `resetScratch` and `finalize`
        // stay null. Upstream falls back for a missing reallocate or scratch
        // pair and never calls a missing finalize
        // (`Headers/SheenBidi/SBAllocator.h:103-136`), and nothing in this
        // configuration reaches the growing `List` that would need the first
        // one.
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

/// How many blocks this allocator will track at once. One algorithm object and
/// its bookkeeping is a handful; a request past this returns null, which
/// SheenBidi reports as an allocation failure, rather than growing an unbounded
/// table inside a demonstration.
const max_live_blocks = 64;

/// What the two callbacks below tally.
///
/// The blocks themselves come from `backing`, which is the caller's allocator
/// and not SheenBidi's, so the memory is one the test framework can see: a leak
/// in this code is `std.testing`'s to report, not an invisible one inside a
/// third-party allocator. Each block's size is kept here because
/// `std.mem.Allocator` frees by slice and the release callback is given only a
/// pointer.
const Counters = struct {
    backing: std.mem.Allocator,
    allocated: usize = 0,
    freed: usize = 0,
    live: [max_live_blocks]struct { address: usize, bytes: usize } =
        @splat(.{ .address = 0, .bytes = 0 }),

    /// How many blocks are held right now. Each object is released before the
    /// count is printed, so a correct scope reports zero.
    fn liveCount(self: *const Counters) usize {
        var live: usize = 0;
        for (self.live) |slot| {
            if (slot.bytes != 0) live += 1;
        }
        return live;
    }
};

/// `SBAllocatorAllocateBlockFunc`, `Headers/SheenBidi/SBAllocator.h:36`.
///
/// The block is aligned for a pointer, not for a byte: `ObjectCreate`
/// (`Source/Core/Object.c`) stores an atomic reference count and the finalize
/// function pointer in it, so a byte-aligned block would be the wrong shape.
/// An exhausted table answers null, which is the failure the header defines.
fn countersBlock(size: sheenbidi.CodeUnitIndex, info: ?*anyopaque) callconv(.c) ?*anyopaque {
    const counters: *Counters = @ptrCast(@alignCast(info orelse return null));
    // A zero-byte request is the one size the header's protocol cannot
    // express usefully here: a block of zero bytes has no address to record.
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

/// The provider this run should load, from `--provider <path>` or from
/// `SHEENBIDI_PROVIDER`.
///
/// Both are explicit. Nothing here looks in a default location or falls back
/// to a linked copy: a runtime-loading build that was not told which file to
/// load reports that it was not told, rather than loading something else.
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

/// Say which variable is missing. An error name on its own would send the next
/// person into the loader instead of to the command line.
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