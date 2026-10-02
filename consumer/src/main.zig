//! A consumer of the `sheenbidi` package.
//!
//! This program does what a text-layout engine does with a bidi library: it
//! takes a paragraph, asks for its base level, asks for the runs it has to lay
//! out, and asks which of its mirrored characters are inside a right-to-left
//! run and therefore have to be drawn as their mirror image.
//!
//! The text is the published conformance row at
//! `Tools/Unicode/BidiCharacterTest.txt` line 45, the same Hebrew-and-brackets
//! example as line 44 run under a right-to-left paragraph:
//!
//!   <HEBREW ALEF> <HEBREW BET> ( <HEBREW GIMEL> <HEBREW DALET> [ & e f ] . ) g h
//!
//! Everything asserted below is Unicode's published answer for that row, keyed
//! by its own line number. It is written out as a literal rather than read from
//! the fixture, because a consumer of a published package does not have the
//! package's test data — which is exactly what makes this an independent check
//! of the run order rather than a restatement of it.

const std = @import("std");
const sheenbidi = @import("sheenbidi");

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

/// Field 1: `1` is an explicit right-to-left paragraph.
const paragraph_base: sheenbidi.BaseLevel = .{ .explicit = 1 };

/// Field 2.
const expected_paragraph_level: sheenbidi.Level = 1;

/// Field 3 collapsed into runs, in the visual order a layout engine walks.
/// Seven Hebrew characters at level 1, two Latin letters raised to level 2
/// inside the squared brackets, three more at level 1, and the last two Latin
/// letters at level 2.
const expected_runs = [_]sheenbidi.Run{
    .{ .offset = 12, .length = 2, .level = 2 },
    .{ .offset = 9, .length = 3, .level = 1 },
    .{ .offset = 7, .length = 2, .level = 2 },
    .{ .offset = 0, .length = 7, .level = 1 },
};

/// Field 4.
const expected_order = [_]sheenbidi.CodeUnitIndex{
    12, 13, 11, 10, 9, 7, 8, 6, 5, 4, 3, 2, 1, 0,
};

/// The mirrors the line contains, in the order the locator reports them.
/// Only characters inside a right-to-left run are mirrored, and the runs are
/// walked in visual order, so the squared bracket at index 9 comes first.
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

pub fn main() !void {
    var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // `text` is borrowed: it must stay alive and unmodified until the last
    // object below is deinitialised.
    const source = sheenbidi.Source.fromUtf32(&text);

    var algorithm = try sheenbidi.Algorithm.create(source);
    defer algorithm.deinit();

    var paragraph = try algorithm.createParagraph(0, source.codeUnits(), paragraph_base);
    defer paragraph.deinit();

    try w.print("sheenbidi consumer, version {s}\n", .{sheenbidi.versionString()});
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

    const order = try line.visualOrder(std.heap.page_allocator);
    defer std.heap.page_allocator.free(order);

    if (order.len != expected_order.len) return error.VisualOrderLengthMismatch;
    try w.print("visual order:", .{});
    for (order, 0..) |index, i| {
        if (index != expected_order[i]) return error.VisualOrderMismatch;
        try w.print(" {d}", .{index});
    }
    try w.print("\n", .{});

    // The Hebrew letters head the line logically and are drawn last, which is
    // what a right-to-left paragraph means; the two Latin runs keep their own
    // left-to-right order inside it.
    try w.print("drawn first {d} (g), drawn last {d} (alef)\n", .{ order[0], order[order.len - 1] });
    if (order[0] != 12 or order[order.len - 1] != 0) return error.RunOrderMismatch;

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

    try w.print("all published values for row 45 reproduced\n", .{});
    try w.flush();
}
