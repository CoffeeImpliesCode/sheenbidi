//! Parser for `Tools/Unicode/BidiTest.txt`, the property-value conformance test
//! published with UAX #9.
//!
//! The file has three kinds of line, documented in its own header:
//!
//! ```
//! @Levels:  <levels>     applies to every data row until the next one
//! @Reorder: <indices>    applies to every data row until the next one
//! <classes>; <bitset>    one data row
//! ```
//!
//! `<classes>` is a space-separated list of `Bidi_Class` names and `<bitset>` is
//! a hexadecimal set of paragraph directions: `1` for automatic, `2` for an
//! explicit left-to-right paragraph, `4` for an explicit right-to-left one. The
//! same expected levels and order apply to each direction the bitset selects.
//! Any other line beginning with `@` is to be ignored, which is how the file
//! reserves room for future directives.
//!
//! Because a data row names property values rather than code points, the
//! iterator also publishes the row as code points, using the verified
//! representatives from `bidi_class.zig`. That mapping is checked against
//! Unicode's own `DerivedBidiClass.txt` by the caller; without the check the
//! rows would silently describe a different property sequence.

const std = @import("std");
const bidi_class = @import("bidi_class.zig");
const level_lists = @import("level.zig");

pub const BidiClass = bidi_class.BidiClass;
pub const ResolvedLevel = level_lists.ResolvedLevel;

/// The paragraph directions a row is to be run with, from its bitset.
///
/// Every field defaults to `false` so a partial literal is valid and no caller
/// can leave a direction undecided by omission.
pub const Directions = packed struct {
    /// Bit `1`: rules P2 and P3 decide the level.
    auto_ltr: bool = false,
    /// Bit `2`: an explicit level of `0`.
    ltr: bool = false,
    /// Bit `4`: an explicit level of `1`.
    rtl: bool = false,
};

pub const Error = error{MalformedLine} || std.mem.Allocator.Error;

/// One data row together with the block it belongs to. Every slice points into
/// the iterator's own buffers and stays valid only until the next call to
/// `next`.
pub const Row = struct {
    /// 1-based line number in the fixture, so a failure can name the row.
    line_number: usize,
    /// The property values, in order.
    classes: []const BidiClass,
    /// The same row as code points, one per class.
    text: []const u32,
    /// The directions this row must hold for.
    directions: Directions,
    /// The `@Levels` block's levels, one entry per class.
    levels: []const ResolvedLevel,
    /// The `@Reorder` block's visual order, one entry per class that is not
    /// `x`.
    order: []const usize,
};

pub const Iterator = struct {
    allocator: std.mem.Allocator,
    bytes: []const u8,
    cursor: usize,
    line_number: usize,
    classes: std.ArrayList(BidiClass),
    text: std.ArrayList(u32),
    block_levels: std.ArrayList(ResolvedLevel),
    block_order: std.ArrayList(usize),
    /// Whether an `@Levels` line has been seen.
    have_levels: bool = false,
    /// Whether a `@Reorder` line has been seen.
    have_order: bool = false,
    /// The bitset of the row currently being parsed.
    directions: Directions = .{},

    pub fn init(allocator: std.mem.Allocator, bytes: []const u8) Iterator {
        return .{
            .allocator = allocator,
            .bytes = bytes,
            .cursor = 0,
            .line_number = 0,
            .classes = .empty,
            .text = .empty,
            .block_levels = .empty,
            .block_order = .empty,
        };
    }

    pub fn deinit(self: *Iterator) void {
        self.classes.deinit(self.allocator);
        self.text.deinit(self.allocator);
        self.block_levels.deinit(self.allocator);
        self.block_order.deinit(self.allocator);
        self.* = undefined;
    }

    /// Advances to the next data row, or returns `null` at the end of the file.
    /// Directive, comment and blank lines do not produce a row, but they do
    /// update the block the following rows inherit.
    pub fn next(self: *Iterator) Error!?Row {
        while (self.cursor < self.bytes.len) {
            const line_start = self.cursor;
            var line_end = line_start;
            while (line_end < self.bytes.len and self.bytes[line_end] != '\n') line_end += 1;
            self.cursor = if (line_end < self.bytes.len) line_end + 1 else line_end;
            self.line_number += 1;

            const line = stripComment(self.bytes[line_start..line_end]);
            if (line.len == 0) continue;

            if (std.mem.startsWith(u8, line, "@Levels:")) {
                try level_lists.parseLevels(
                    &self.block_levels,
                    self.allocator,
                    line["@Levels:".len..],
                );
                self.have_levels = true;
                continue;
            }
            if (std.mem.startsWith(u8, line, "@Reorder:")) {
                try level_lists.parseIndices(
                    &self.block_order,
                    self.allocator,
                    line["@Reorder:".len..],
                );
                self.have_order = true;
                continue;
            }
            if (line[0] == '@') continue;

            try self.parseRow(line);
            return self.row();
        }
        return null;
    }

    fn row(self: *const Iterator) Row {
        return .{
            .line_number = self.line_number,
            .classes = self.classes.items,
            .text = self.text.items,
            .directions = self.directions,
            .levels = self.block_levels.items,
            .order = self.block_order.items,
        };
    }

    fn parseRow(self: *Iterator, line: []const u8) Error!void {
        if (!self.have_levels or !self.have_order) return Error.MalformedLine;

        var fields = std.mem.splitScalar(u8, line, ';');
        const classes_field = fields.next() orelse return Error.MalformedLine;
        const bitset_field = fields.next() orelse return Error.MalformedLine;
        // The format is exactly two fields; a third means this parser and the
        // file have diverged.
        if (fields.next() != null) return Error.MalformedLine;

        self.classes.clearRetainingCapacity();
        self.text.clearRetainingCapacity();
        var tokens = std.mem.tokenizeAny(u8, classes_field, " \t");
        while (tokens.next()) |token| {
            const class = BidiClass.parseName(token) orelse return Error.MalformedLine;
            try self.classes.append(self.allocator, class);
            try self.text.append(self.allocator, class.representative());
        }

        const bitset = std.fmt.parseInt(u8, std.mem.trim(u8, bitset_field, " \t\r"), 16) catch {
            return Error.MalformedLine;
        };
        self.directions = .{
            .auto_ltr = (bitset & 0x1) != 0,
            .ltr = (bitset & 0x2) != 0,
            .rtl = (bitset & 0x4) != 0,
        };
        if (!self.directions.auto_ltr and !self.directions.ltr and !self.directions.rtl) {
            return Error.MalformedLine;
        }

        // One level per property value, and one visual index per value that
        // survives rule X9. A row that breaks either rule would put an index
        // out of bounds in the harness, so it is rejected here.
        if (self.classes.items.len != self.block_levels.items.len) return Error.MalformedLine;
        if (self.block_order.items.len != level_lists.survivingCount(self.block_levels.items)) {
            return Error.MalformedLine;
        }
    }
};

fn stripComment(line: []const u8) []const u8 {
    const without_comment = if (std.mem.findScalar(u8, line, '#')) |hash| line[0..hash] else line;
    return std.mem.trim(u8, without_comment, " \t\r");
}
