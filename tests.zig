//! Behaviour tests for the `sheenbidi` package.
//!
//! The centrepiece is conformance. `BidiCharacterTest.txt` and `BidiTest.txt`
//! are the two test files Unicode publishes with UAX #9, and both are shipped
//! unmodified in `Tools/Unicode/`. Every data row of both is replayed here
//! against the facade, and the resolved paragraph level, the resolved levels
//! and the visual order are compared with the published expectation. That is
//! an independent known answer: the expectations were produced by the Unicode
//! consortium, not by this fork and not by SheenBidi.
//!
//! `BidiTest.txt` states its cases as Bidi_Class property values rather than
//! code points, so the harness turns each value into one representative code
//! point (`zig/conformance/bidi_class.zig`). Those representatives are checked
//! against Unicode's own `DerivedBidiClass.txt`, which is also shipped in
//! `Tools/Unicode/` — without that check a wrong representative would quietly
//! replay a different property sequence from the one the fixture describes.
//!
//! The remaining tests are boundary cases the fixtures cannot reach: rule P1
//! across a CRLF pair, rule L1 on a trailing whitespace run, the three
//! encodings of one text, rejected ranges, the ownership rules between the
//! reference-counted objects, and the codepoint, script and mirror lookups.
//!
//! This file is the test root. Because it sits at the package root, its module
//! root directory is the package directory, which is what lets `@embedFile`
//! reach `Tools/Unicode/`.

const std = @import("std");
const sheenbidi = @import("sheenbidi");
const bidi_class = @import("zig/conformance/bidi_class.zig");
const bidi_test = @import("zig/conformance/bidi_test.zig");
const character_test = @import("zig/conformance/character_test.zig");

const bidi_character_test_bytes = @embedFile("Tools/Unicode/BidiCharacterTest.txt");
const bidi_test_bytes = @embedFile("Tools/Unicode/BidiTest.txt");
const derived_bidi_class_bytes = @embedFile("Tools/Unicode/DerivedBidiClass.txt");

/// The two files name themselves in their first line; the counts below are the
/// number of data rows each contains, so a pass can state that it covered the
/// whole file instead of stopping at the first error-free prefix.
const bidi_character_test_rows = 91707;
const bidi_test_rows = 490846;
/// Data rows times the directions each row's bitset selects.
const bidi_test_cases = 770241;

const TestError = sheenbidi.Error || error{ConformanceFailure};

fn fail(fixture: []const u8, line_number: usize, what: []const u8) error{ConformanceFailure} {
    std.debug.print("{s} line {d}: wrong {s}\n", .{ fixture, line_number, what });
    return error.ConformanceFailure;
}

/// Compares a built line with one fixture row's expectation.
///
/// Every code unit of the line must be covered by exactly one run, each code
/// unit the fixture gives a level for must carry that level, and the visual
/// order must list the surviving code units left to right exactly as the
/// fixture does.
///
/// A code unit the fixture marks `x` was removed by rule X9 and is therefore
/// not rendered; the standard assigns it no level, so the harness only
/// requires that it is covered by a run and that it is skipped in the visual
/// order. Pinning it to a particular number would pin an implementation
/// detail.
fn checkLineAgainstFixture(
    allocator: std.mem.Allocator,
    line: sheenbidi.Line,
    levels: []const character_test.ResolvedLevel,
    order: []const usize,
    fixture: []const u8,
    line_number: usize,
) TestError!void {
    if (line.length() != levels.len) return fail(fixture, line_number, "line length");

    const observed = try allocator.alloc(?sheenbidi.Level, line.length());
    defer allocator.free(observed);
    for (observed) |*slot| slot.* = null;

    for (line.runs()) |run| {
        var index: usize = 0;
        while (index < run.length) : (index += 1) {
            const at = run.offset - line.offset() + index;
            if (at >= observed.len or observed[at] != null) {
                return fail(fixture, line_number, "run coverage");
            }
            observed[at] = run.level;
        }
    }

    for (observed, 0..) |entry, at| {
        const level = entry orelse return fail(fixture, line_number, "run coverage");
        switch (levels[at]) {
            .removed => {},
            .level => |expected| {
                if (level != expected) return fail(fixture, line_number, "resolved level");
            },
        }
    }

    const visual = try line.visualOrder(allocator);
    defer allocator.free(visual);
    var position: usize = 0;
    for (visual) |index| {
        switch (levels[index]) {
            .removed => continue,
            .level => {},
        }
        if (position >= order.len or order[position] != index) {
            return fail(fixture, line_number, "visual order");
        }
        position += 1;
    }
    if (position != order.len) return fail(fixture, line_number, "visual order length");
}

/// Replays one row of `BidiCharacterTest.txt`.
fn checkCharacterCase(allocator: std.mem.Allocator, case: character_test.TestCase) TestError!void {
    const source = sheenbidi.Source.fromUtf32(case.text);
    var algorithm = try sheenbidi.Algorithm.create(source);
    defer algorithm.deinit();

    // Field 1 selects the paragraph direction: 0 and 1 are explicit levels,
    // 2 leaves it to rules P2 and P3.
    const base: sheenbidi.BaseLevel = switch (case.paragraph_direction) {
        .ltr => .{ .explicit = 0 },
        .rtl => .{ .explicit = 1 },
        .auto => .auto_ltr,
    };

    var paragraph = try algorithm.createParagraph(0, source.codeUnits(), base);
    defer paragraph.deinit();

    if (paragraph.baseLevel() != case.paragraph_level) {
        return fail("BidiCharacterTest.txt", case.line_number, "paragraph level");
    }

    var line = try paragraph.createLine(paragraph.offset(), paragraph.length());
    defer line.deinit();

    try checkLineAgainstFixture(
        allocator,
        line,
        case.levels,
        case.order,
        "BidiCharacterTest.txt",
        case.line_number,
    );
}

/// Replays one row of `BidiTest.txt` for every paragraph direction its bitset
/// selects. The same expected levels and order apply to each of them.
fn checkBidiTestRow(allocator: std.mem.Allocator, row: bidi_test.Row) TestError!usize {
    const source = sheenbidi.Source.fromUtf32(row.text);
    var cases: usize = 0;

    var bases: [3]sheenbidi.BaseLevel = undefined;
    var count: usize = 0;
    if (row.directions.auto_ltr) {
        bases[count] = .auto_ltr;
        count += 1;
    }
    if (row.directions.ltr) {
        bases[count] = .{ .explicit = 0 };
        count += 1;
    }
    if (row.directions.rtl) {
        bases[count] = .{ .explicit = 1 };
        count += 1;
    }

    for (bases[0..count]) |base| {
        var algorithm = try sheenbidi.Algorithm.create(source);
        defer algorithm.deinit();

        var paragraph = try algorithm.createParagraph(0, source.codeUnits(), base);
        defer paragraph.deinit();

        // The fixture does not state the paragraph level separately; the
        // levels it does state already encode the result, and comparing them
        // is what `checkLineAgainstFixture` does.
        var line = try paragraph.createLine(paragraph.offset(), paragraph.length());
        defer line.deinit();

        try checkLineAgainstFixture(
            allocator,
            line,
            row.levels,
            row.order,
            "BidiTest.txt",
            row.line_number,
        );
        cases += 1;
    }

    return cases;
}

test "conformance: every row of BidiCharacterTest.txt" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var iterator = character_test.Iterator.init(std.testing.allocator, bidi_character_test_bytes);
    defer iterator.deinit();

    var rows: usize = 0;
    while (try iterator.next()) |case| {
        try checkCharacterCase(arena, case);
        _ = arena_state.reset(.retain_capacity);
        rows += 1;
    }

    try std.testing.expectEqual(@as(usize, bidi_character_test_rows), rows);
}

test "conformance: every row and direction of BidiTest.txt" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var iterator = bidi_test.Iterator.init(std.testing.allocator, bidi_test_bytes);
    defer iterator.deinit();

    var rows: usize = 0;
    var cases: usize = 0;
    while (try iterator.next()) |row| {
        cases += try checkBidiTestRow(arena, row);
        _ = arena_state.reset(.retain_capacity);
        rows += 1;
    }

    try std.testing.expectEqual(@as(usize, bidi_test_rows), rows);
    try std.testing.expectEqual(@as(usize, bidi_test_cases), cases);
}

test "conformance: BidiTest representatives match DerivedBidiClass.txt" {
    var table = try bidi_class.Table.parse(std.testing.allocator, derived_bidi_class_bytes);
    defer table.deinit();

    if (table.firstInconsistentRepresentative()) |wrong| {
        std.debug.print("representative for {s} does not have that Bidi_Class\n", .{wrong.name()});
        return error.ConformanceFailure;
    }

    // Anchors that do not depend on the representative table at all, so a
    // table that happened to agree with a broken parser would still fail here.
    try std.testing.expectEqual(bidi_class.BidiClass.r, table.classOf(0x05D0).?);
    try std.testing.expectEqual(bidi_class.BidiClass.al, table.classOf(0x0627).?);
    try std.testing.expectEqual(bidi_class.BidiClass.an, table.classOf(0x0660).?);
    try std.testing.expectEqual(bidi_class.BidiClass.en, table.classOf(0x30).?);
    try std.testing.expectEqual(bidi_class.BidiClass.b, table.classOf(0x0A).?);
    try std.testing.expectEqual(bidi_class.BidiClass.ws, table.classOf(0x20).?);
    try std.testing.expectEqual(bidi_class.BidiClass.fsi, table.classOf(0x2068).?);
    try std.testing.expectEqual(bidi_class.BidiClass.rlo, table.classOf(0x202E).?);
    try std.testing.expectEqual(bidi_class.BidiClass.l, table.classOf(0x0041).?);
    try std.testing.expectEqual(bidi_class.BidiClass.l, table.classOf(0x0061).?);
    try std.testing.expect(table.classOf(0x110000) == null);
}

// ---------------------------------------------------------------------------
// Fixture rows quoted by hand.
//
// The whole file is replayed above. These few rows are named here as well
// because each is the smallest published example of one behaviour, and a
// failure that points at one named row is worth more than one that points at
// a row number in a nine-megabyte file.
// ---------------------------------------------------------------------------

const script_nil: sheenbidi.Script = @intCast(sheenbidi.c.SBScriptNil);
const script_latn: sheenbidi.Script = @intCast(sheenbidi.c.SBScriptLATN);
const script_hebr: sheenbidi.Script = @intCast(sheenbidi.c.SBScriptHEBR);

const general_category_ll: sheenbidi.GeneralCategory = @intCast(sheenbidi.c.SBGeneralCategoryLL);
const general_category_nd: sheenbidi.GeneralCategory = @intCast(sheenbidi.c.SBGeneralCategoryND);
const general_category_mn: sheenbidi.GeneralCategory = @intCast(sheenbidi.c.SBGeneralCategoryMN);
const general_category_zs: sheenbidi.GeneralCategory = @intCast(sheenbidi.c.SBGeneralCategoryZS);
const general_category_cc: sheenbidi.GeneralCategory = @intCast(sheenbidi.c.SBGeneralCategoryCC);
const general_category_ps: sheenbidi.GeneralCategory = @intCast(sheenbidi.c.SBGeneralCategoryPS);
const general_category_sm: sheenbidi.GeneralCategory = @intCast(sheenbidi.c.SBGeneralCategorySM);

/// The run covering `index`, or `null` when the line does not cover it.
fn runAt(line: sheenbidi.Line, index: sheenbidi.CodeUnitIndex) ?sheenbidi.Run {
    for (line.runs()) |run| {
        if (index >= run.offset and index < run.offset + run.length) return run;
    }
    return null;
}

/// Replays one `BidiCharacterTest.txt` row quoted by its line number.
fn expectQuotedRow(
    line_number: usize,
    case_text: []const u32,
    direction: character_test.ParagraphDirection,
    paragraph_level: u8,
    levels: []const character_test.ResolvedLevel,
    order: []const usize,
) TestError!void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    try checkCharacterCase(arena_state.allocator(), .{
        .line_number = line_number,
        .paragraph_direction = direction,
        .paragraph_level = paragraph_level,
        .text = case_text,
        .levels = levels,
        .order = order,
    });
}

fn leveled(value: u8) character_test.ResolvedLevel {
    return .{ .level = value };
}

test "fixture row 44: Hebrew inside paired brackets, left-to-right paragraph" {
    // BidiCharacterTest.txt line 44, the worked example from UAX #9:
    //   <HEBREW ALEF> <HEBREW BET> ( <HEBREW GIMEL> <HEBREW DALET> [ & e f ] . ) g h
    try expectQuotedRow(
        44,
        &.{ 0x05D0, 0x05D1, 0x0028, 0x05D2, 0x05D3, 0x005B, 0x0026, 0x0065, 0x0066, 0x005D, 0x002E, 0x0029, 0x0067, 0x0068 },
        .ltr,
        0,
        &.{ leveled(1), leveled(1), leveled(0), leveled(1), leveled(1), leveled(0), leveled(0), leveled(0), leveled(0), leveled(0), leveled(0), leveled(0), leveled(0), leveled(0) },
        &.{ 1, 0, 2, 4, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13 },
    );
}

test "fixture row 45: the same brackets under a right-to-left paragraph" {
    // BidiCharacterTest.txt line 45. Same text as row 44 with direction 1, and
    // the Latin letters inside the bracket pair move to level 2.
    try expectQuotedRow(
        45,
        &.{ 0x05D0, 0x05D1, 0x0028, 0x05D2, 0x05D3, 0x005B, 0x0026, 0x0065, 0x0066, 0x005D, 0x002E, 0x0029, 0x0067, 0x0068 },
        .rtl,
        1,
        &.{ leveled(1), leveled(1), leveled(1), leveled(1), leveled(1), leveled(1), leveled(1), leveled(2), leveled(2), leveled(1), leveled(1), leveled(1), leveled(2), leveled(2) },
        &.{ 12, 13, 11, 10, 9, 7, 8, 6, 5, 4, 3, 2, 1, 0 },
    );
}

test "fixture row 256: rule L1 resets a segment separator in the line only" {
    // BidiCharacterTest.txt line 256:
    //   <ARABIC-INDIC DIGIT ONE> <TAB> ( <ARABIC-INDIC DIGIT TWO> )
    //
    // The published line levels are `2 0 1 2 1`: the tab is a segment
    // separator, and rule L1 clause 1 resets it to the paragraph level. The
    // paragraph's own levels are one step earlier in the pipeline and keep the
    // level the neutral rules gave it.
    const text = [_]u32{ 0x0661, 0x0009, 0x0028, 0x0662, 0x0029 };
    const source = sheenbidi.Source.fromUtf32(&text);

    var algorithm = try sheenbidi.Algorithm.create(source);
    defer algorithm.deinit();

    var paragraph = try algorithm.createParagraph(0, source.codeUnits(), .auto_ltr);
    defer paragraph.deinit();

    try std.testing.expectEqual(@as(sheenbidi.Level, 0), paragraph.baseLevel());
    try std.testing.expectEqualSlices(sheenbidi.Level, &.{ 2, 1, 1, 2, 1 }, paragraph.levels());

    var line = try paragraph.createLine(paragraph.offset(), paragraph.length());
    defer line.deinit();

    const levels = [_]character_test.ResolvedLevel{ leveled(2), leveled(0), leveled(1), leveled(2), leveled(1) };
    try checkLineAgainstFixture(
        std.testing.allocator,
        line,
        &levels,
        &.{ 0, 1, 4, 3, 2 },
        "BidiCharacterTest.txt row 256",
        256,
    );

    // Every code unit here is its own run, and the array is in visual order:
    // the Arabic-Indic digit, the tab, the closing bracket, the digit it
    // encloses, and the opening bracket.
    const runs = line.runs();
    try std.testing.expectEqual(@as(usize, 5), runs.len);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 0), runs[0].offset);
    try std.testing.expectEqual(@as(sheenbidi.Level, 2), runs[0].level);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 1), runs[1].offset);
    try std.testing.expectEqual(@as(sheenbidi.Level, 0), runs[1].level);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 4), runs[2].offset);
    try std.testing.expectEqual(@as(sheenbidi.Level, 1), runs[2].level);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 3), runs[3].offset);
    try std.testing.expectEqual(@as(sheenbidi.Level, 2), runs[3].level);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 2), runs[4].offset);
    try std.testing.expectEqual(@as(sheenbidi.Level, 1), runs[4].level);
    for (runs) |run| try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 1), run.length);
}

test "paragraph boundary: rule P1 and a CRLF pair" {
    // UAX #9 P1: "split text into paragraphs ... at each paragraph separator",
    // and a CRLF pair is one separator, not two. The rule is also stated in
    // Headers/SheenBidi/SBAlgorithm.h:52.
    const text = "ab\r\ncd\nef";
    const source = sheenbidi.Source.fromUtf8(text);

    var algorithm = try sheenbidi.Algorithm.create(source);
    defer algorithm.deinit();

    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 9), source.codeUnits());

    // The first paragraph ends after the LF that terminates the CRLF pair.
    const first = try algorithm.paragraphBoundary(0, 9);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 4), first.length);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 2), first.separator_length);

    // A lone LF is one code unit.
    const second = try algorithm.paragraphBoundary(4, 5);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 3), second.length);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 1), second.separator_length);

    // A range with no separator is a whole paragraph with no separator, and a
    // range that ends exactly at a boundary reports nothing.
    const third = try algorithm.paragraphBoundary(7, 2);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 2), third.length);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 0), third.separator_length);
    const empty = try algorithm.paragraphBoundary(9, 0);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 0), empty.length);

    // `bidiTypes()` is indexed by code unit and reports the derived
    // Bidi_Class of the code point that code unit belongs to. The two code
    // units of the CRLF pair are U+000D and U+000A, both `B`
    // (`Tools/Unicode/DerivedBidiClass.txt`: `000A ; B`, `000D ; B`), and the
    // code unit before them is U+0062 LATIN SMALL LETTER B, which is `L`
    // (`0061..007A ; L`).
    const types = algorithm.bidiTypes();
    try std.testing.expectEqual(sheenbidi.bidi_type_l, types[1]);
    try std.testing.expectEqual(sheenbidi.bidi_type_b, types[2]);
    try std.testing.expectEqual(sheenbidi.bidi_type_b, types[3]);

    var paragraph = try algorithm.createParagraph(4, 5, .auto_ltr);
    defer paragraph.deinit();
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 4), paragraph.offset());
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 3), paragraph.length());
}

test "line rule L1 clause 4: a trailing whitespace run is reset" {
    // UAX #9 L1: "On each line, reset the embedding level of the following
    // characters to the paragraph embedding level: ... 4. Any sequence of
    // whitespace characters ... at the end of the line."
    //
    // `a` then a right-to-left embedding, so the Hebrew letter and the space
    // that follows it sit at level 1 while the paragraph level is 0. The
    // paragraph keeps the space at level 1; the line resets it to 0.
    const text = [_]u32{ 0x0061, 0x202B, 0x05D0, 0x0020 };
    const source = sheenbidi.Source.fromUtf32(&text);

    var algorithm = try sheenbidi.Algorithm.create(source);
    defer algorithm.deinit();

    var paragraph = try algorithm.createParagraph(0, source.codeUnits(), .{ .explicit = 0 });
    defer paragraph.deinit();

    try std.testing.expectEqual(@as(sheenbidi.Level, 0), paragraph.baseLevel());
    const paragraph_levels = paragraph.levels();
    try std.testing.expectEqual(@as(sheenbidi.Level, 0), paragraph_levels[0]);
    try std.testing.expectEqual(@as(sheenbidi.Level, 1), paragraph_levels[2]);
    try std.testing.expectEqual(@as(sheenbidi.Level, 1), paragraph_levels[3]);

    var line = try paragraph.createLine(paragraph.offset(), paragraph.length());
    defer line.deinit();

    // The line agrees with the paragraph on the letter and differs on the
    // space: index 3 is the trailing whitespace run L1 resets.
    try std.testing.expectEqual(@as(sheenbidi.Level, 0), runAt(line, 0).?.level);
    try std.testing.expectEqual(@as(sheenbidi.Level, 1), runAt(line, 2).?.level);
    try std.testing.expectEqual(@as(sheenbidi.Level, 0), runAt(line, 3).?.level);

    // Nothing here is at an odd level any more, so nothing is reordered.
    const order = try line.visualOrder(std.testing.allocator);
    defer std.testing.allocator.free(order);
    try std.testing.expectEqualSlices(sheenbidi.CodeUnitIndex, &.{ 0, 1, 2, 3 }, order);
}

test "one text, three encodings: code unit counts differ, levels do not" {
    // "a" + GRINNING FACE + HEBREW ALEF. UTF-8 spends four code units on the
    // emoji, UTF-16 spends two, UTF-32 spends one, and every SheenBidi offset
    // counts code units — so the same text has three different index spaces.
    const utf8_text = "a\u{1F600}\u{05D0}";
    const utf16_text = [_]u16{ 0x0061, 0xD83D, 0xDE00, 0x05D0 };
    const utf32_text = [_]u32{ 0x0061, 0x1F600, 0x05D0 };

    const utf8_source = sheenbidi.Source.fromUtf8(utf8_text);
    const utf16_source = sheenbidi.Source.fromUtf16(&utf16_text);
    const utf32_source = sheenbidi.Source.fromUtf32(&utf32_text);

    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 7), utf8_source.codeUnits());
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 4), utf16_source.codeUnits());
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 3), utf32_source.codeUnits());

    try std.testing.expectEqual(@as(usize, 7), utf8_source.byteLength());
    try std.testing.expectEqual(@as(usize, 8), utf16_source.byteLength());
    try std.testing.expectEqual(@as(usize, 12), utf32_source.byteLength());

    // The bidirectional result is a property of the text, not of the
    // encoding: the Latin letter is at level 0 and the Hebrew letter at
    // level 1, whichever units they are counted in. Each `hebrew_index` is the
    // first code unit of HEBREW ALEF in that encoding.
    const cases = [_]struct {
        source: sheenbidi.Source,
        hebrew_index: sheenbidi.CodeUnitIndex,
    }{
        .{ .source = utf8_source, .hebrew_index = 5 },
        .{ .source = utf16_source, .hebrew_index = 3 },
        .{ .source = utf32_source, .hebrew_index = 2 },
    };

    for (cases) |case| {
        var algorithm = try sheenbidi.Algorithm.create(case.source);
        defer algorithm.deinit();

        var paragraph = try algorithm.createParagraph(0, case.source.codeUnits(), .auto_ltr);
        defer paragraph.deinit();

        try std.testing.expectEqual(@as(sheenbidi.Level, 0), paragraph.baseLevel());
        try std.testing.expectEqual(@as(sheenbidi.Level, 0), paragraph.levels()[0]);
        try std.testing.expectEqual(@as(sheenbidi.Level, 1), paragraph.levels()[case.hebrew_index]);

        var line = try paragraph.createLine(paragraph.offset(), paragraph.length());
        defer line.deinit();
        try std.testing.expectEqual(case.source.codeUnits(), line.length());
        try std.testing.expectEqual(@as(sheenbidi.Level, 1), runAt(line, case.hebrew_index).?.level);
        try std.testing.expectEqual(@as(sheenbidi.Level, 0), runAt(line, 0).?.level);
    }
}

test "out-of-range and empty requests are rejected before the C sees them" {
    const text = "ab";
    const source = sheenbidi.Source.fromUtf8(text);
    const max = std.math.maxInt(sheenbidi.CodeUnitIndex);

    // The empty source is the one rejection upstream also performs:
    // SBCodepointSequenceIsValid requires a non-zero length, so
    // SBAlgorithmCreate returns NULL for it.
    try std.testing.expectError(sheenbidi.Error.EmptySource, sheenbidi.Algorithm.create(sheenbidi.Source.fromUtf8("")));
    try std.testing.expectError(sheenbidi.Error.EmptySource, sheenbidi.Algorithm.create(sheenbidi.Source.fromUtf16(&[_]u16{})));
    try std.testing.expectError(sheenbidi.Error.EmptySource, sheenbidi.Algorithm.create(sheenbidi.Source.fromUtf32(&[_]u32{})));

    var algorithm = try sheenbidi.Algorithm.create(source);
    defer algorithm.deinit();

    try std.testing.expectError(sheenbidi.Error.RangeOutOfBounds, algorithm.paragraphBoundary(3, 0));
    try std.testing.expectError(sheenbidi.Error.RangeOutOfBounds, algorithm.paragraphBoundary(0, max));
    try std.testing.expectError(sheenbidi.Error.RangeOutOfBounds, algorithm.paragraphBoundary(1, max));
    try std.testing.expectError(sheenbidi.Error.RangeOutOfBounds, algorithm.createParagraph(2, 1, .auto_ltr));
    try std.testing.expectError(sheenbidi.Error.RangeOutOfBounds, algorithm.createParagraph(0, max, .auto_ltr));
    try std.testing.expectError(sheenbidi.Error.EmptyRange, algorithm.createParagraph(0, 0, .auto_ltr));

    var paragraph = try algorithm.createParagraph(0, 2, .auto_ltr);
    defer paragraph.deinit();

    try std.testing.expectError(sheenbidi.Error.RangeOutOfBounds, paragraph.createLine(2, 1));
    try std.testing.expectError(sheenbidi.Error.RangeOutOfBounds, paragraph.createLine(0, 3));
    try std.testing.expectError(sheenbidi.Error.RangeOutOfBounds, paragraph.createLine(0, max));
    try std.testing.expectError(sheenbidi.Error.EmptyRange, paragraph.createLine(0, 0));

    // A base level is one of the two sentinels or a level in range; anything
    // above SBLevelMax is neither.
    try std.testing.expectError(sheenbidi.Error.InvalidBaseLevel, (sheenbidi.BaseLevel{ .explicit = 126 }).toC());
    try std.testing.expectError(sheenbidi.Error.InvalidBaseLevel, (sheenbidi.BaseLevel{ .explicit = 255 }).toC());
}

test "base level: automatic, explicit, and the SBLevelMax boundary" {
    const rtl_text = [_]u32{0x05D0};
    const neutral_text = [_]u32{0x0030};

    // Automatic: rules P2 and P3 find the first strong type; a text with no
    // strong type falls back to the sentinel's default.
    const auto_ltr_cases = [_]struct { text: []const u32, expected: sheenbidi.Level }{
        .{ .text = &rtl_text, .expected = 1 },
        .{ .text = &neutral_text, .expected = 0 },
    };
    for (auto_ltr_cases) |case| {
        const source = sheenbidi.Source.fromUtf32(case.text);
        var algorithm = try sheenbidi.Algorithm.create(source);
        defer algorithm.deinit();
        var paragraph = try algorithm.createParagraph(0, source.codeUnits(), .auto_ltr);
        defer paragraph.deinit();
        try std.testing.expectEqual(case.expected, paragraph.baseLevel());
    }

    const default_rtl_text = [_]u32{0x0030};
    {
        const source = sheenbidi.Source.fromUtf32(&default_rtl_text);
        var algorithm = try sheenbidi.Algorithm.create(source);
        defer algorithm.deinit();
        var paragraph = try algorithm.createParagraph(0, source.codeUnits(), .auto_rtl);
        defer paragraph.deinit();
        try std.testing.expectEqual(@as(sheenbidi.Level, 1), paragraph.baseLevel());
    }

    // Explicit: rules P2 and P3 are skipped. And the boundary is `>=`, not
    // `>`: SBLevelMax itself is read as "not explicit" by upstream
    // (Source/API/SBParagraph.c, DetermineParagraphLevel), so a right-to-left
    // text at that level resolves through P2/P3 to 1 and a neutral text to 0.
    const explicit_cases = [_]struct { text: []const u32, base: sheenbidi.BaseLevel, expected: sheenbidi.Level }{
        .{ .text = &rtl_text, .base = .{ .explicit = 0 }, .expected = 0 },
        .{ .text = &rtl_text, .base = .{ .explicit = 1 }, .expected = 1 },
        .{ .text = &rtl_text, .base = .{ .explicit = sheenbidi.level_max }, .expected = 1 },
        .{ .text = &neutral_text, .base = .{ .explicit = sheenbidi.level_max }, .expected = 0 },
        .{ .text = &rtl_text, .base = .{ .explicit = 124 }, .expected = 124 },
    };
    for (explicit_cases) |case| {
        const source = sheenbidi.Source.fromUtf32(case.text);
        var algorithm = try sheenbidi.Algorithm.create(source);
        defer algorithm.deinit();
        var paragraph = try algorithm.createParagraph(0, source.codeUnits(), case.base);
        defer paragraph.deinit();
        try std.testing.expectEqual(case.expected, paragraph.baseLevel());
    }

    // 124 is the highest explicit level upstream honours verbatim, and the
    // Hebrew letter then rises to 125 under rule I1 — "for all characters with
    // an even (left-to-right) embedding level, those of type R go up one
    // level" (`Source/UBA/IsolatingRun.c:443`). SBLevelMax itself, in the two
    // cases above, never survives as an explicit level at all.
    {
        const source = sheenbidi.Source.fromUtf32(&rtl_text);
        var algorithm = try sheenbidi.Algorithm.create(source);
        defer algorithm.deinit();
        var paragraph = try algorithm.createParagraph(0, source.codeUnits(), .{ .explicit = 124 });
        defer paragraph.deinit();
        try std.testing.expectEqual(@as(sheenbidi.Level, 124), paragraph.baseLevel());
        try std.testing.expectEqual(@as(sheenbidi.Level, 125), paragraph.levels()[0]);
    }
}

test "bidi types cover every code unit and partition into the four families" {
    // One entry per code unit, not per code point: a code point that occupies
    // several code units contributes its type once and BN for the rest
    // (Source/API/SBCodepointSequence.c, SBCodepointSequenceDetermineBidiTypes).
    const multi_unit = "a\u{1F600}\u{05D0}";
    {
        const source = sheenbidi.Source.fromUtf8(multi_unit);
        var algorithm = try sheenbidi.Algorithm.create(source);
        defer algorithm.deinit();

        const types = algorithm.bidiTypes();
        try std.testing.expectEqual(@as(usize, 7), types.len);
        try std.testing.expectEqual(sheenbidi.bidi_type_l, types[0]);
        try std.testing.expectEqual(sheenbidi.bidi_type_on, types[1]);
        // The remaining three code units of the emoji are continuation units.
        try std.testing.expectEqual(sheenbidi.bidi_type_bn, types[2]);
        try std.testing.expectEqual(sheenbidi.bidi_type_bn, types[3]);
        try std.testing.expectEqual(sheenbidi.bidi_type_bn, types[4]);
        // HEBREW ALEF is two code units: the type on the first, BN on the
        // second.
        try std.testing.expectEqual(sheenbidi.bidi_type_r, types[5]);
        try std.testing.expectEqual(sheenbidi.bidi_type_bn, types[6]);
    }

    // The four classifiers partition the type space. The counts are read out
    // of Headers/SheenBidi/SBBidiType.h: three strong, seven weak, four
    // neutral, nine format, plus Nil.
    const all = [_]sheenbidi.BidiType{
        sheenbidi.bidi_type_nil,
        sheenbidi.bidi_type_l,
        sheenbidi.bidi_type_r,
        sheenbidi.bidi_type_al,
        sheenbidi.bidi_type_bn,
        sheenbidi.bidi_type_nsm,
        sheenbidi.bidi_type_an,
        sheenbidi.bidi_type_en,
        sheenbidi.bidi_type_et,
        sheenbidi.bidi_type_es,
        sheenbidi.bidi_type_cs,
        sheenbidi.bidi_type_ws,
        sheenbidi.bidi_type_s,
        sheenbidi.bidi_type_b,
        sheenbidi.bidi_type_on,
        sheenbidi.bidi_type_lri,
        sheenbidi.bidi_type_rli,
        sheenbidi.bidi_type_fsi,
        sheenbidi.bidi_type_pdi,
        sheenbidi.bidi_type_lre,
        sheenbidi.bidi_type_rle,
        sheenbidi.bidi_type_lro,
        sheenbidi.bidi_type_rlo,
        sheenbidi.bidi_type_pdf,
    };
    var strong: usize = 0;
    var weak: usize = 0;
    var neutral: usize = 0;
    var format: usize = 0;
    for (all) |t| {
        if (sheenbidi.bidiTypeIsStrong(t)) strong += 1;
        if (sheenbidi.bidiTypeIsWeak(t)) weak += 1;
        if (sheenbidi.bidiTypeIsNeutral(t)) neutral += 1;
        if (sheenbidi.bidiTypeIsFormat(t)) format += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), strong);
    try std.testing.expectEqual(@as(usize, 7), weak);
    try std.testing.expectEqual(@as(usize, 4), neutral);
    try std.testing.expectEqual(@as(usize, 9), format);
    try std.testing.expectEqual(@as(usize, all.len), strong + weak + neutral + format + 1);
}

test "codepoint lookup: bidi type, general category, script and mirror" {
    try std.testing.expectEqual(sheenbidi.bidi_type_l, sheenbidi.codepointBidiType(0x0061));
    try std.testing.expectEqual(sheenbidi.bidi_type_r, sheenbidi.codepointBidiType(0x05D0));
    try std.testing.expectEqual(sheenbidi.bidi_type_al, sheenbidi.codepointBidiType(0x0627));
    try std.testing.expectEqual(sheenbidi.bidi_type_en, sheenbidi.codepointBidiType(0x0030));
    try std.testing.expectEqual(sheenbidi.bidi_type_lri, sheenbidi.codepointBidiType(0x2066));
    try std.testing.expectEqual(sheenbidi.bidi_type_b, sheenbidi.codepointBidiType(0x000A));

    try std.testing.expectEqual(general_category_ll, sheenbidi.codepointGeneralCategory(0x0061));
    try std.testing.expectEqual(general_category_nd, sheenbidi.codepointGeneralCategory(0x0030));
    try std.testing.expectEqual(general_category_mn, sheenbidi.codepointGeneralCategory(0x0300));
    try std.testing.expectEqual(general_category_zs, sheenbidi.codepointGeneralCategory(0x0020));
    try std.testing.expectEqual(general_category_cc, sheenbidi.codepointGeneralCategory(0x000A));
    try std.testing.expectEqual(general_category_ps, sheenbidi.codepointGeneralCategory(0x0028));
    try std.testing.expectEqual(general_category_sm, sheenbidi.codepointGeneralCategory(0x002B));

    try std.testing.expect(sheenbidi.generalCategoryIsLetter(general_category_ll));
    try std.testing.expect(sheenbidi.generalCategoryIsMark(general_category_mn));
    try std.testing.expect(sheenbidi.generalCategoryIsNumber(general_category_nd));
    try std.testing.expect(sheenbidi.generalCategoryIsPunctuation(general_category_ps));
    try std.testing.expect(sheenbidi.generalCategoryIsSymbol(general_category_sm));
    try std.testing.expect(sheenbidi.generalCategoryIsSeparator(general_category_zs));
    try std.testing.expect(sheenbidi.generalCategoryIsOther(general_category_cc));
    try std.testing.expect(!sheenbidi.generalCategoryIsLetter(general_category_nd));
    try std.testing.expect(!sheenbidi.generalCategoryIsNumber(general_category_ll));

    try std.testing.expectEqual(script_hebr, sheenbidi.codepointScript(0x05D0));
    try std.testing.expectEqual(script_latn, sheenbidi.codepointScript(0x0061));
    // 'H' 'e' 'b' 'r', big-endian, read out of Source/API/SBBase.c:581.
    try std.testing.expectEqual(@as(u32, 0x48656272), sheenbidi.scriptUnicodeTag(script_hebr));

    try std.testing.expectEqual(@as(sheenbidi.Codepoint, 0x0029), sheenbidi.codepointMirror(0x0028));
    try std.testing.expectEqual(@as(sheenbidi.Codepoint, 0x0028), sheenbidi.codepointMirror(0x0029));
    try std.testing.expectEqual(@as(sheenbidi.Codepoint, 0), sheenbidi.codepointMirror(0x0061));

    try std.testing.expect(sheenbidi.codepointIsSurrogate(0xD800));
    try std.testing.expect(sheenbidi.codepointIsSurrogate(0xDFFF));
    try std.testing.expect(!sheenbidi.codepointIsValid(0xD800));
    try std.testing.expect(!sheenbidi.codepointIsValid(0x110000));
    try std.testing.expect(sheenbidi.codepointIsValid(0x10FFFF));
    try std.testing.expect(sheenbidi.codepointIsValid(0x0000));
}

test "codepoint decoding walks the source in every encoding and reports out-of-range indices" {
    // LATIN SMALL LETTER A, GRINNING FACE, HEBREW LETTER ALEF. The three code
    // points are the same in each encoding; only the index space changes, so
    // the same walk is asserted against all three encodings with the code unit
    // index each code point starts at. A multi-unit code point is what makes
    // the three index spaces differ: the emoji is four code units in UTF-8,
    // two in UTF-16 and one in UTF-32, and HEBREW LETTER ALEF is two, one and
    // one.
    const utf8_text = "a\u{1F600}\u{05D0}";
    const utf16_text = [_]u16{ 0x0061, 0xD83D, 0xDE00, 0x05D0 };
    const utf32_text = [_]u32{ 0x0061, 0x1F600, 0x05D0 };

    const cases = [_]struct {
        source: sheenbidi.Source,
        emoji_at: sheenbidi.CodeUnitIndex,
        emoji_len: sheenbidi.CodeUnitIndex,
        hebrew_at: sheenbidi.CodeUnitIndex,
    }{
        .{ .source = sheenbidi.Source.fromUtf8(utf8_text), .emoji_at = 1, .emoji_len = 4, .hebrew_at = 5 },
        .{ .source = sheenbidi.Source.fromUtf16(&utf16_text), .emoji_at = 1, .emoji_len = 2, .hebrew_at = 3 },
        .{ .source = sheenbidi.Source.fromUtf32(&utf32_text), .emoji_at = 1, .emoji_len = 1, .hebrew_at = 2 },
    };

    for (cases) |case| {
        const total = case.source.codeUnits();

        const first = sheenbidi.codepointAt(case.source, 0);
        try std.testing.expectEqual(@as(sheenbidi.Codepoint, 0x0061), first.codepoint);
        try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 1), first.next);

        const emoji = sheenbidi.codepointAt(case.source, case.emoji_at);
        try std.testing.expectEqual(@as(sheenbidi.Codepoint, 0x1F600), emoji.codepoint);
        try std.testing.expectEqual(case.emoji_at + case.emoji_len, emoji.next);

        const hebrew = sheenbidi.codepointAt(case.source, case.hebrew_at);
        try std.testing.expectEqual(@as(sheenbidi.Codepoint, 0x05D0), hebrew.codepoint);
        try std.testing.expectEqual(total, hebrew.next);

        // An index at the very end is how a caller asks for the code point
        // before the end, and a code point never starts at its own end.
        const last = sheenbidi.codepointBefore(case.source, total);
        try std.testing.expectEqual(@as(sheenbidi.Codepoint, 0x05D0), last.codepoint);
        try std.testing.expectEqual(case.hebrew_at, last.start);

        const before_emoji = sheenbidi.codepointBefore(case.source, case.emoji_at);
        try std.testing.expectEqual(@as(sheenbidi.Codepoint, 0x0061), before_emoji.codepoint);
        try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 0), before_emoji.start);

        const past_end = sheenbidi.codepointAt(case.source, total);
        try std.testing.expectEqual(sheenbidi.codepoint_invalid, past_end.codepoint);
        try std.testing.expectEqual(total, past_end.next);

        const at_zero = sheenbidi.codepointBefore(case.source, 0);
        try std.testing.expectEqual(sheenbidi.codepoint_invalid, at_zero.codepoint);
        try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 0), at_zero.start);
    }
}

test "mirror locator: only odd-level runs mirror, and it holds the line" {
    // The bracketed Arabic-Indic digits of BidiCharacterTest.txt line 256.
    // The Arabic-Indic digits sit at level 2 and are not considered; the two
    // brackets sit at level 1 and each reports the other.
    const text = [_]u32{ 0x0661, 0x0009, 0x0028, 0x0662, 0x0029 };
    const source = sheenbidi.Source.fromUtf32(&text);

    var algorithm = try sheenbidi.Algorithm.create(source);
    defer algorithm.deinit();

    var paragraph = try algorithm.createParagraph(0, source.codeUnits(), .auto_ltr);
    defer paragraph.deinit();

    var line = try paragraph.createLine(paragraph.offset(), paragraph.length());
    defer line.deinit();

    var locator = try sheenbidi.MirrorLocator.create();
    defer locator.deinit();

    locator.loadLine(line);

    // The runs are in visual order, so the closing bracket at index 4 is
    // reached before the opening one at index 2.
    try std.testing.expect(locator.moveNext());
    const closing = locator.mirror();
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 4), closing.index);
    try std.testing.expectEqual(@as(sheenbidi.Codepoint, 0x0029), closing.codepoint);
    try std.testing.expectEqual(@as(sheenbidi.Codepoint, 0x0028), closing.mirrored);

    try std.testing.expect(locator.moveNext());
    const opening = locator.mirror();
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 2), opening.index);
    try std.testing.expectEqual(@as(sheenbidi.Codepoint, 0x0028), opening.codepoint);
    try std.testing.expectEqual(@as(sheenbidi.Codepoint, 0x0029), opening.mirrored);

    // The digits at level 2 are never reported.
    try std.testing.expect(!locator.moveNext());

    // "The locator will be reset after locating last mirror"
    // (Headers/SheenBidi/SBMirrorLocator.h:73), so the same walk repeats.
    try std.testing.expect(locator.moveNext());
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 4), locator.mirror().index);

    locator.reset();
    try std.testing.expect(locator.moveNext());
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 4), locator.mirror().index);
}

test "mirror locator keeps its line alive after the handle is released" {
    // SBMirrorLocatorLoadLine retains the line (Source/API/SBMirrorLocator.c:57),
    // so the line object survives the caller releasing its own reference. The
    // source buffer belongs to the caller and is still alive here, which is the
    // other half of the borrow contract.
    const text = [_]u32{ 0x0661, 0x0009, 0x0028, 0x0662, 0x0029 };
    const source = sheenbidi.Source.fromUtf32(&text);

    var algorithm = try sheenbidi.Algorithm.create(source);
    defer algorithm.deinit();

    var paragraph = try algorithm.createParagraph(0, source.codeUnits(), .auto_ltr);
    defer paragraph.deinit();

    var holder = try sheenbidi.MirrorLocator.create();
    defer holder.deinit();

    // No `defer` on the line: this test releases the one reference it owns at
    // the point the locator has its own, which is the transition being checked.
    var line = try paragraph.createLine(paragraph.offset(), paragraph.length());
    holder.loadLine(line);
    line.deinit();

    try std.testing.expect(holder.moveNext());
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 4), holder.mirror().index);
    try std.testing.expect(holder.moveNext());
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 2), holder.mirror().index);
    try std.testing.expect(!holder.moveNext());
}

test "script locator: runs of one script over a mixed string" {
    // Three Latin letters and a space, then two Hebrew letters. The space is
    // Common, and a Common code point joins the run it sits in, so the first
    // run is four code units long rather than three.
    const text = [_]u32{ 0x0061, 0x0062, 0x0063, 0x0020, 0x05D0, 0x05D1 };
    const source = sheenbidi.Source.fromUtf32(&text);

    var locator = try sheenbidi.ScriptLocator.create();
    defer locator.deinit();

    locator.load(source);

    try std.testing.expect(locator.moveNext());
    const latin = locator.run();
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 0), latin.offset);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 4), latin.length);
    try std.testing.expectEqual(script_latn, latin.script);

    try std.testing.expect(locator.moveNext());
    const hebrew = locator.run();
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 4), hebrew.offset);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 2), hebrew.length);
    try std.testing.expectEqual(script_hebr, hebrew.script);

    try std.testing.expect(!locator.moveNext());
    try std.testing.expectEqual(script_nil, locator.run().script);

    locator.reset();
    try std.testing.expect(locator.moveNext());
    try std.testing.expectEqual(script_latn, locator.run().script);
}

test "a paragraph outlives its algorithm and retain keeps the object alive" {
    const text = "car means \u{05D0}\u{05D1}\u{05D2}.";
    const source = sheenbidi.Source.fromUtf8(text);

    var algorithm = try sheenbidi.Algorithm.create(source);
    var paragraph = try algorithm.createParagraph(0, source.codeUnits(), .auto_ltr);

    // SBAlgorithmCreateParagraph retains the algorithm, so the paragraph is
    // usable once this handle is gone.
    algorithm.deinit();

    try std.testing.expectEqual(@as(sheenbidi.Level, 0), paragraph.baseLevel());
    try std.testing.expectEqual(@as(sheenbidi.Level, 1), paragraph.levels()[10]);
    try std.testing.expectEqual(@as(sheenbidi.Level, 1), paragraph.levels()[15]);

    var line = try paragraph.createLine(paragraph.offset(), paragraph.length());
    defer line.deinit();
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 17), line.length());
    // U+002E FULL STOP is `CS` (`Tools/Unicode/DerivedBidiClass.txt`:
    // `002E..002F ; CS`), which rule W6 turns into a neutral because it is not
    // between two numbers. Rule N1 finds no agreement — the Hebrew run on its
    // left is strong R, the end of the paragraph is L — so rule N2 gives it the
    // embedding direction, level 0. Unicode publishes exactly that for the
    // property sequence: `BidiTest.txt` line 47657 `L R CS; 3` sits in the
    // `@Levels: 0 1 0` / `@Reorder: 0 1 2` block at lines 47652-47653. The
    // line therefore has three runs, not two.
    try std.testing.expectEqual(@as(sheenbidi.Level, 0), paragraph.levels()[16]);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 3), line.runCount());

    // The retained handle and the original are the same object: releasing one
    // leaves the other valid.
    var retained = paragraph.retain();
    paragraph.deinit();

    try std.testing.expectEqual(@as(sheenbidi.Level, 0), retained.baseLevel());
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 0), retained.offset());
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 17), retained.length());

    var second = try retained.createLine(retained.offset(), retained.length());
    defer second.deinit();
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 17), second.length());

    const order = try second.visualOrder(std.testing.allocator);
    defer std.testing.allocator.free(order);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 17), order.len);
    // The Latin prefix stays where it is and the right-to-left run is drawn
    // from its own end, so the full stop — back at the paragraph level — is
    // drawn last, after the Hebrew letters it precedes logically.
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 0), order[0]);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 15), order[10]);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 10), order[15]);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 16), order[16]);

    retained.deinit();
}

test "retain returns a second reference to the same object" {
    // HEBREW ALEF, LEFT PARENTHESIS, LATIN SMALL LETTER A. The bracket sits in
    // the right-to-left run, so the mirror locator reaches it; the Latin
    // letter is raised to level 2 by rule I2.
    const text = [_]u32{ 0x05D0, 0x0028, 0x0061 };
    const source = sheenbidi.Source.fromUtf32(&text);

    var algorithm = try sheenbidi.Algorithm.create(source);
    var kept_algorithm = algorithm.retain();
    algorithm.deinit();
    try std.testing.expectEqual(@as(usize, 3), kept_algorithm.bidiTypes().len);

    var paragraph = try kept_algorithm.createParagraph(0, source.codeUnits(), .auto_ltr);
    var kept_paragraph = paragraph.retain();
    paragraph.deinit();
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 3), kept_paragraph.length());

    var line = try kept_paragraph.createLine(kept_paragraph.offset(), kept_paragraph.length());
    var kept_line = line.retain();
    line.deinit();
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 3), kept_line.length());

    var locator = try sheenbidi.ScriptLocator.create();
    var kept_locator = locator.retain();
    locator.deinit();
    kept_locator.load(source);
    try std.testing.expect(kept_locator.moveNext());
    const run = kept_locator.run();
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 0), run.offset);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 2), run.length);
    try std.testing.expectEqual(script_hebr, run.script);
    kept_locator.deinit();

    var mirrors = try sheenbidi.MirrorLocator.create();
    var kept_mirrors = mirrors.retain();
    mirrors.deinit();
    kept_mirrors.loadLine(kept_line);
    try std.testing.expect(kept_mirrors.moveNext());
    const mirror = kept_mirrors.mirror();
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 1), mirror.index);
    try std.testing.expectEqual(@as(sheenbidi.Codepoint, 0x0029), mirror.mirrored);
    kept_mirrors.deinit();

    kept_line.deinit();
    kept_paragraph.deinit();
    kept_algorithm.deinit();
}
