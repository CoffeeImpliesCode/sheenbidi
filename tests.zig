// SPDX-License-Identifier: Apache-2.0
//
//! Conformance tests for the SheenBidi facade.

const std = @import("std");
const sheenbidi = @import("sheenbidi");
const bidi_class = @import("zig/conformance/bidi_class.zig");
const bidi_test = @import("zig/conformance/bidi_test.zig");
const character_test = @import("zig/conformance/character_test.zig");

/// Environment variable naming the shared library for runtime-loading tests.
const provider_variable = "SHEENBIDI_PROVIDER";

/// Loads the configured provider once in runtime-loading mode; linked mode is a no-op.
fn nativeReady() void {
    if (comptime !sheenbidi.runtime_loaded) return;
    if (sheenbidi.loadedSource() != null) return;

    var buffer: [4096]u8 = undefined;
    const value = std.testing.environ.getAlloc(std.testing.allocator, provider_variable) catch
        missingProvider();
    defer std.testing.allocator.free(value);
    if (value.len == 0 or value.len > buffer.len) missingProvider();
    @memcpy(buffer[0..value.len], value);
    sheenbidi.load(.{ .path = buffer[0..value.len] }) catch |err| {
        std.debug.print(
            "tests.zig: loading " ++ provider_variable ++ " = \"{s}\" failed: {t}\n",
            .{ buffer[0..value.len], err },
        );
        @panic("tests.zig: the provider named by " ++ provider_variable ++
            " did not load; nothing below this line ran");
    };
}

fn missingProvider() noreturn {
    @panic(
        "tests.zig: this is a runtime-loading build and " ++ provider_variable ++
            " is not set. Point it at a shared object exporting the fifty-one " ++
            "entry points of the stable SheenBidi surface, for example the one " ++
            "`zig build -Dlinkage=dynamic` installs, and export it for the whole " ++
            "`zig build` invocation: the build cannot inject a path into a run " ++
            "step's environment.",
    );
}

const bidi_character_test_bytes = @embedFile("Tools/Unicode/BidiCharacterTest.txt");
const bidi_test_bytes = @embedFile("Tools/Unicode/BidiTest.txt");
const derived_bidi_class_bytes = @embedFile("Tools/Unicode/DerivedBidiClass.txt");

/// Expected row counts in the complete Unicode fixtures.
const bidi_character_test_rows = 91707;
const bidi_test_rows = 490846;
/// Expected cases after direction expansion.
const bidi_test_cases = 770241;

const TestError = sheenbidi.Error || error{ConformanceFailure};

fn fail(fixture: []const u8, line_number: usize, what: []const u8) error{ConformanceFailure} {
    std.debug.print("{s} line {d}: wrong {s}\n", .{ fixture, line_number, what });
    return error.ConformanceFailure;
}

/// Checks run coverage, resolved levels, and visual order against one fixture row.
/// X9-removed units need coverage but no fixed level or visual position.
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

    // Direction 2 leaves paragraph direction to rules P2 and P3.
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
    nativeReady();
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
    nativeReady();
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

    // Independent anchors prevent a broken parser and matching table from passing.
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

// Selected fixture cases for focused failure messages.

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
    nativeReady();
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
    nativeReady();
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
    nativeReady();
    // UAX #9 L1 resets the tab on the line, not in the paragraph.
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
    nativeReady();
    // UAX #9 P1 treats CRLF as one paragraph separator (SBAlgorithm.h).
    const text = "ab\r\ncd\nef";
    const source = sheenbidi.Source.fromUtf8(text);

    var algorithm = try sheenbidi.Algorithm.create(source);
    defer algorithm.deinit();

    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 9), source.codeUnits());

    const first = try algorithm.paragraphBoundary(0, 9);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 4), first.length);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 2), first.separator_length);

    const second = try algorithm.paragraphBoundary(4, 5);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 3), second.length);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 1), second.separator_length);

    const third = try algorithm.paragraphBoundary(7, 2);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 2), third.length);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 0), third.separator_length);
    const empty = try algorithm.paragraphBoundary(9, 0);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 0), empty.length);

    // The CRLF code units are Bidi_Class B; preceding b is L.
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
    nativeReady();
    // L1 resets trailing whitespace to the paragraph level on a line.
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

    try std.testing.expectEqual(@as(sheenbidi.Level, 0), runAt(line, 0).?.level);
    try std.testing.expectEqual(@as(sheenbidi.Level, 1), runAt(line, 2).?.level);
    try std.testing.expectEqual(@as(sheenbidi.Level, 0), runAt(line, 3).?.level);

    const order = try line.visualOrder(std.testing.allocator);
    defer std.testing.allocator.free(order);
    try std.testing.expectEqualSlices(sheenbidi.CodeUnitIndex, &.{ 0, 1, 2, 3 }, order);
}

test "one text, three encodings: code unit counts differ, levels do not" {
    nativeReady();
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
    nativeReady();
    const text = "ab";
    const source = sheenbidi.Source.fromUtf8(text);
    const max = std.math.maxInt(sheenbidi.CodeUnitIndex);

    // Upstream rejects empty codepoint sequences.
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

    // Explicit levels above the sentinel are invalid.
    try std.testing.expectError(sheenbidi.Error.InvalidBaseLevel, (sheenbidi.BaseLevel{ .explicit = 126 }).toC());
    try std.testing.expectError(sheenbidi.Error.InvalidBaseLevel, (sheenbidi.BaseLevel{ .explicit = 255 }).toC());
}

test "base level: automatic, explicit, and the SBLevelMax boundary" {
    nativeReady();
    const rtl_text = [_]u32{0x05D0};
    const neutral_text = [_]u32{0x0030};

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

    // SBLevelMax is a sentinel, not an explicit level (SBParagraph.c).
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

    // Level 124 is honored; rule I1 raises this R to 125 (IsolatingRun.c).
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
    nativeReady();
    // Multi-unit code points contribute their type once, then BN continuations (SBCodepointSequence.c).
    const multi_unit = "a\u{1F600}\u{05D0}";
    {
        const source = sheenbidi.Source.fromUtf8(multi_unit);
        var algorithm = try sheenbidi.Algorithm.create(source);
        defer algorithm.deinit();

        const types = algorithm.bidiTypes();
        try std.testing.expectEqual(@as(usize, 7), types.len);
        try std.testing.expectEqual(sheenbidi.bidi_type_l, types[0]);
        try std.testing.expectEqual(sheenbidi.bidi_type_on, types[1]);
        try std.testing.expectEqual(sheenbidi.bidi_type_bn, types[2]);
        try std.testing.expectEqual(sheenbidi.bidi_type_bn, types[3]);
        try std.testing.expectEqual(sheenbidi.bidi_type_bn, types[4]);
        try std.testing.expectEqual(sheenbidi.bidi_type_r, types[5]);
        try std.testing.expectEqual(sheenbidi.bidi_type_bn, types[6]);
    }

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
    nativeReady();
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
    nativeReady();
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

        // The end index selects the previous code point.
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
    nativeReady();
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

    try std.testing.expect(!locator.moveNext());

    // Upstream resets the locator after the last mirror (SBMirrorLocator.h).
    try std.testing.expect(locator.moveNext());
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 4), locator.mirror().index);

    locator.reset();
    try std.testing.expect(locator.moveNext());
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 4), locator.mirror().index);
}

test "mirror locator keeps its line alive after the handle is released" {
    nativeReady();
    // The locator retains its line; the source remains borrowed (SBMirrorLocator.c).
    const text = [_]u32{ 0x0661, 0x0009, 0x0028, 0x0662, 0x0029 };
    const source = sheenbidi.Source.fromUtf32(&text);

    var algorithm = try sheenbidi.Algorithm.create(source);
    defer algorithm.deinit();

    var paragraph = try algorithm.createParagraph(0, source.codeUnits(), .auto_ltr);
    defer paragraph.deinit();

    var holder = try sheenbidi.MirrorLocator.create();
    defer holder.deinit();

    // Release our line reference after the locator retains it.
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
    nativeReady();
    // Common script joins the adjacent Latin run.
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
    nativeReady();
    const text = "car means \u{05D0}\u{05D1}\u{05D2}.";
    const source = sheenbidi.Source.fromUtf8(text);

    var algorithm = try sheenbidi.Algorithm.create(source);
    var paragraph = try algorithm.createParagraph(0, source.codeUnits(), .auto_ltr);

    // Paragraph retains its algorithm.
    algorithm.deinit();

    try std.testing.expectEqual(@as(sheenbidi.Level, 0), paragraph.baseLevel());
    try std.testing.expectEqual(@as(sheenbidi.Level, 1), paragraph.levels()[10]);
    try std.testing.expectEqual(@as(sheenbidi.Level, 1), paragraph.levels()[15]);

    var line = try paragraph.createLine(paragraph.offset(), paragraph.length());
    defer line.deinit();
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 17), line.length());
    // U+002E is neutral at paragraph end, producing a third run.
    try std.testing.expectEqual(@as(sheenbidi.Level, 0), paragraph.levels()[16]);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 3), line.runCount());

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
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 0), order[0]);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 15), order[10]);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 10), order[15]);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 16), order[16]);

    retained.deinit();
}

test "retain returns a second reference to the same object" {
    nativeReady();
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

test "an allocator without a required member is refused, and a complete one takes every block" {
    nativeReady();

    // Upstream calls both callbacks unconditionally; reject omissions before allocation (SBAllocator.c).
    try std.testing.expectError(
        sheenbidi.Error.MissingProtocolFunction,
        sheenbidi.Allocator.create(.{ .deallocateBlock = ledgerFree }, null),
    );
    try std.testing.expectError(
        sheenbidi.Error.MissingProtocolFunction,
        sheenbidi.Allocator.create(.{ .allocateBlock = ledgerBlock }, null),
    );

    var ledger: Ledger = .{ .backing = std.testing.allocator };
    var allocator = try sheenbidi.Allocator.create(.{
        .allocateBlock = ledgerBlock,
        .deallocateBlock = ledgerFree,
    }, &ledger);
    defer allocator.deinit();

    const previous = sheenbidi.c.SBAllocatorGetDefault();
    sheenbidi.c.SBAllocatorSetDefault(allocator.ref);
    // Restore the process default before allocator deinit.
    defer sheenbidi.c.SBAllocatorSetDefault(previous);

    {
        const units = [_]u32{ 0x0061, 0x05D0 };
        var algorithm = try sheenbidi.Algorithm.create(sheenbidi.Source.fromUtf32(&units));
        algorithm.deinit();
    }

    try std.testing.expect(ledger.taken > 0);
    try std.testing.expectEqual(ledger.taken, ledger.returned);
    try std.testing.expectEqual(@as(usize, 0), ledger.live());
}

test "the direct decoders walk both encodings and refuse the indices upstream refuses" {
    nativeReady();

    // Decoding positions count code units, not code points.
    const utf8_units = "a\u{1F600}\u{05D0}";
    const utf16_units = [_]u16{ 0x0061, 0xD83D, 0xDE00, 0x05D0 };

    const utf8_steps = [_]struct {
        at: sheenbidi.CodeUnitIndex,
        codepoint: sheenbidi.Codepoint,
    }{
        .{ .at = 0, .codepoint = 0x0061 },
        .{ .at = 1, .codepoint = 0x1F600 },
        .{ .at = 5, .codepoint = 0x05D0 },
    };
    var index: sheenbidi.CodeUnitIndex = 0;
    for (utf8_steps) |step| {
        const decoded = sheenbidi.codepointDecodeNextFromUtf8(utf8_units, index);
        try std.testing.expectEqual(step.at, index);
        try std.testing.expectEqual(step.codepoint, decoded.codepoint);
        index = decoded.next;
    }
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, utf8_units.len), index);

    const utf16_steps = [_]struct {
        at: sheenbidi.CodeUnitIndex,
        codepoint: sheenbidi.Codepoint,
    }{
        .{ .at = 0, .codepoint = 0x0061 },
        .{ .at = 1, .codepoint = 0x1F600 },
        .{ .at = 3, .codepoint = 0x05D0 },
    };
    var index16: sheenbidi.CodeUnitIndex = 0;
    for (utf16_steps) |step| {
        const decoded = sheenbidi.codepointDecodeNextFromUtf16(&utf16_units, index16);
        try std.testing.expectEqual(step.at, index16);
        try std.testing.expectEqual(step.codepoint, decoded.codepoint);
        index16 = decoded.next;
    }
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, utf16_units.len), index16);

    // Backward decoding must match the corresponding forward start.
    const back8 = sheenbidi.codepointDecodePreviousFromUtf8(utf8_units, utf8_units.len);
    try std.testing.expectEqual(@as(sheenbidi.Codepoint, 0x05D0), back8.codepoint);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 5), back8.start);
    const back16 = sheenbidi.codepointDecodePreviousFromUtf16(&utf16_units, utf16_units.len);
    try std.testing.expectEqual(@as(sheenbidi.Codepoint, 0x05D0), back16.codepoint);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 3), back16.start);

    // Incomplete UTF-8 reports faulty and stops at the invalid byte (SBCodepoint.c).
    const broken_utf8 = [_]u8{ 0xE2, 0x28 };
    const broken = sheenbidi.codepointDecodeNextFromUtf8(&broken_utf8, 0);
    try std.testing.expectEqual(sheenbidi.codepoint_faulty, broken.codepoint);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 1), broken.next);

    // An unpaired UTF-16 surrogate reports faulty (SBCodepoint.c).
    const lone_high = [_]u16{0xD83D};
    const high = sheenbidi.codepointDecodeNextFromUtf16(&lone_high, 0);
    try std.testing.expectEqual(sheenbidi.codepoint_faulty, high.codepoint);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 1), high.next);
    const lone_low = [_]u16{0xDE00};
    const low = sheenbidi.codepointDecodeNextFromUtf16(&lone_low, 0);
    try std.testing.expectEqual(sheenbidi.codepoint_faulty, low.codepoint);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 1), low.next);

    // Out-of-range indices return invalid; backward index zero wraps upstream (SBCodepoint.c).
    const past_end = sheenbidi.codepointDecodeNextFromUtf8(utf8_units, utf8_units.len);
    try std.testing.expectEqual(sheenbidi.codepoint_invalid, past_end.codepoint);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, utf8_units.len), past_end.next);
    const at_zero = sheenbidi.codepointDecodePreviousFromUtf8(utf8_units, 0);
    try std.testing.expectEqual(sheenbidi.codepoint_invalid, at_zero.codepoint);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, 0), at_zero.start);
    const past_end16 = sheenbidi.codepointDecodePreviousFromUtf16(&utf16_units, utf16_units.len + 1);
    try std.testing.expectEqual(sheenbidi.codepoint_invalid, past_end16.codepoint);
    try std.testing.expectEqual(@as(sheenbidi.CodeUnitIndex, utf16_units.len + 1), past_end16.start);
}

test "OpenType and Unicode script tags are two mappings, not one" {
    nativeReady();

    // OpenType tags are lower-case; Unicode tags are title-case (SBBase.c).
    try std.testing.expectEqual(@as(u32, 0x48656272), sheenbidi.scriptUnicodeTag(script_hebr));
    try std.testing.expectEqual(@as(u32, 0x68656272), sheenbidi.scriptOpenTypeTag(script_hebr));
    try std.testing.expectEqual(@as(u32, 0x4C61746E), sheenbidi.scriptUnicodeTag(script_latn));
    try std.testing.expectEqual(@as(u32, 0x6C61746E), sheenbidi.scriptOpenTypeTag(script_latn));

    // OpenType defaults to DFLT; Unicode tags default to zero (SBBase.c).
    try std.testing.expectEqual(@as(u32, 0x44464C54), sheenbidi.scriptOpenTypeTag(script_nil));
    try std.testing.expectEqual(@as(u32, 0), sheenbidi.scriptUnicodeTag(script_nil));

    // Run script tags map directly to OpenType tags.
    try std.testing.expectEqual(script_hebr, sheenbidi.codepointScript(0x05D0));
    try std.testing.expectEqual(script_latn, sheenbidi.codepointScript(0x0061));
}

/// How many blocks the test allocator below tracks at once.
const max_blocks = 32;

/// Tracks allocated blocks and their sizes for callback cleanup.
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

/// Matches the C allocation callback; null signals allocation failure.
fn ledgerBlock(size: sheenbidi.CodeUnitIndex, info: ?*anyopaque) callconv(.c) ?*anyopaque {
    const ledger: *Ledger = @ptrCast(@alignCast(info orelse return null));
    if (size == 0) return null;
    for (&ledger.blocks) |*slot| {
        if (slot.bytes != 0) continue;
        const block = ledger.backing.alignedAlloc(u8, .fromByteUnits(@alignOf(usize)), size) catch
            return null;
        slot.* = .{ .address = @intFromPtr(block.ptr), .bytes = block.len };
        ledger.taken += 1;
        return block.ptr;
    }
    return null;
}

/// `SBAllocatorDeallocateBlockFunc`, `Headers/SheenBidi/SBAllocator.h:60`.
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
