//! Parser for `Tools/Unicode/BidiCharacterTest.txt`, the character conformance
//! test published with UAX #9.
//!
//! The file format is documented in its own header, and this parser implements
//! exactly that and nothing more:
//!
//! ```
//! # comment
//! <code points> ; <paragraph direction> ; <paragraph level> ; <levels> ; <order>
//! ```
//!
//! * field 0 is hexadecimal code points separated by spaces;
//! * field 1 is `0` for left-to-right, `1` for right-to-left, `2` for
//!   automatic, i.e. rules P2 and P3;
//! * field 2 is the embedding level the paragraph resolved to;
//! * field 3 is one resolved level per code point, with `x` where rule X9
//!   removed the code point;
//! * field 4 is the left-to-right visual order, listing the indices of the
//!   code points that survive rule X9, and nothing else.
//!
//! Blank lines and everything from `#` to the end of a line are ignored, which
//! is what makes the file's own documentation parseable as a comment block.
//!
//! The iterator reuses its buffers between rows, so a full pass over the file
//! allocates only as much as its longest row needs.

const std = @import("std");
const level_lists = @import("level.zig");

/// One entry of field 3: either a level, or a code point rule X9 removed.
pub const ResolvedLevel = level_lists.ResolvedLevel;

/// Field 1, the paragraph direction the row is to be run with.
pub const ParagraphDirection = enum(u2) {
    /// `0`: an explicit left-to-right paragraph.
    ltr = 0,
    /// `1`: an explicit right-to-left paragraph.
    rtl = 1,
    /// `2`: rules P2 and P3 decide.
    auto = 2,
};

pub const Error = error{MalformedLine} || std.mem.Allocator.Error;

/// One data row. Every slice points into the iterator's own buffers and stays
/// valid only until the next call to `next`.
pub const TestCase = struct {
    /// 1-based line number in the fixture, so a failure can name the row.
    line_number: usize,
    paragraph_direction: ParagraphDirection,
    /// Field 2.
    paragraph_level: u8,
    /// Field 0, ready to be borrowed as a UTF-32 source.
    text: []const u32,
    /// Field 3, one entry per code point.
    levels: []const ResolvedLevel,
    /// Field 4, one entry per code point that survives rule X9.
    order: []const usize,
};

pub const Iterator = struct {
    allocator: std.mem.Allocator,
    bytes: []const u8,
    cursor: usize,
    line_number: usize,
    text: std.ArrayList(u32),
    levels: std.ArrayList(ResolvedLevel),
    order: std.ArrayList(usize),
    /// Field 1 of the row currently being parsed.
    direction: ParagraphDirection = .ltr,
    /// Field 2 of the row currently being parsed.
    paragraph_level: u8 = 0,

    pub fn init(allocator: std.mem.Allocator, bytes: []const u8) Iterator {
        return .{
            .allocator = allocator,
            .bytes = bytes,
            .cursor = 0,
            .line_number = 0,
            .text = .empty,
            .levels = .empty,
            .order = .empty,
        };
    }

    pub fn deinit(self: *Iterator) void {
        self.text.deinit(self.allocator);
        self.levels.deinit(self.allocator);
        self.order.deinit(self.allocator);
        self.* = undefined;
    }

    /// Advances to the next data row, or returns `null` at the end of the
    /// file. Comments and blank lines are skipped and do not produce a row.
    pub fn next(self: *Iterator) Error!?TestCase {
        while (self.cursor < self.bytes.len) {
            const line_start = self.cursor;
            var line_end = line_start;
            while (line_end < self.bytes.len and self.bytes[line_end] != '\n') line_end += 1;
            self.cursor = if (line_end < self.bytes.len) line_end + 1 else line_end;
            self.line_number += 1;

            const line = trimToContent(self.bytes[line_start..line_end]);
            if (line.len == 0) continue;

            try self.parseLine(line);
            return self.row();
        }
        return null;
    }

    fn row(self: *const Iterator) TestCase {
        return .{
            .line_number = self.line_number,
            .paragraph_direction = self.direction,
            .paragraph_level = self.paragraph_level,
            .text = self.text.items,
            .levels = self.levels.items,
            .order = self.order.items,
        };
    }

    fn parseLine(self: *Iterator, line: []const u8) Error!void {
        var fields = std.mem.splitScalar(u8, line, ';');

        const text_field = fields.next() orelse return Error.MalformedLine;
        const direction_field = fields.next() orelse return Error.MalformedLine;
        const level_field = fields.next() orelse return Error.MalformedLine;
        const levels_field = fields.next() orelse return Error.MalformedLine;
        const order_field = fields.next() orelse return Error.MalformedLine;
        // The format is exactly five fields; a sixth means this parser and the
        // file have diverged, and guessing which fields to ignore would hide
        // it.
        if (fields.next() != null) return Error.MalformedLine;

        try parseCodepoints(&self.text, self.allocator, text_field);
        self.direction = parseDirection(direction_field) orelse return Error.MalformedLine;
        self.paragraph_level = std.fmt.parseInt(u8, trimField(level_field), 10) catch {
            return Error.MalformedLine;
        };
        try level_lists.parseLevels(&self.levels, self.allocator, levels_field);
        try level_lists.parseIndices(&self.order, self.allocator, order_field);

        // The fixture is consistent by construction: one level per code point,
        // and one visual index per code point that survives rule X9. A row that
        // breaks either rule would put an index out of bounds in the harness,
        // so it is rejected here instead.
        if (self.text.items.len != self.levels.items.len) return Error.MalformedLine;
        if (self.order.items.len != level_lists.survivingCount(self.levels.items)) {
            return Error.MalformedLine;
        }
    }
};

/// Strips a trailing comment and surrounding whitespace from a line.
fn trimToContent(line: []const u8) []const u8 {
    const without_comment = if (std.mem.findScalar(u8, line, '#')) |hash| line[0..hash] else line;
    return std.mem.trim(u8, without_comment, " \t\r");
}

fn trimField(field: []const u8) []const u8 {
    return std.mem.trim(u8, field, " \t\r");
}

fn parseDirection(field: []const u8) ?ParagraphDirection {
    const text = trimField(field);
    if (text.len != 1) return null;
    return switch (text[0]) {
        '0' => .ltr,
        '1' => .rtl,
        '2' => .auto,
        else => null,
    };
}

fn parseCodepoints(list: *std.ArrayList(u32), allocator: std.mem.Allocator, field: []const u8) Error!void {
    list.clearRetainingCapacity();
    var tokens = std.mem.tokenizeAny(u8, field, " \t");
    while (tokens.next()) |token| {
        const value = std.fmt.parseInt(u32, token, 16) catch return Error.MalformedLine;
        try list.append(allocator, value);
    }
}
