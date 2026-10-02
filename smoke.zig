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
//! Nothing here depends on timing, on a locale or on an environment variable,
//! so the output is the same on every host and a change in it is a change in
//! behaviour. The version line is printed rather than asserted: which upstream
//! release this binary was linked against belongs to the provenance gate.

const std = @import("std");
const sheenbidi = @import("sheenbidi");

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

pub fn main() !void {
    var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    try w.print("sheenbidi smoke\n", .{});
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

    const order = try line.visualOrder(std.heap.page_allocator);
    defer std.heap.page_allocator.free(order);

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
}
