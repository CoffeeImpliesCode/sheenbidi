//! The `Bidi_Class` property values, and the bundled table that assigns them.
//!
//! Two things live here that the conformance harness needs and that would be
//! dishonest to guess at:
//!
//! 1. The names `BidiTest.txt` writes in its input column, parsed into an enum.
//! 2. A representative code point for each value, so a sequence of property
//!    values can be turned into real text. `BidiTest.txt` states its cases in
//!    property values, not code points, and says a conforming implementation
//!    may "randomly pick characters from those with the same Bidi_Class
//!    values"; a fixed, verified representative is the deterministic form of
//!    that.
//!
//! The representatives are not taken on trust. `Table` reads
//! `Tools/Unicode/DerivedBidiClass.txt` — Unicode's own derived property file,
//! shipped in this repository — and `representativeIsConsistent` checks every
//! representative against it. Without that check a wrong representative would
//! silently test a different property sequence from the one the fixture
//! describes.

const std = @import("std");

/// A `Bidi_Class` value. The 23 values `BidiTest.txt` uses, named as the
/// Unicode property aliases name them.
pub const BidiClass = enum {
    l,
    r,
    al,
    bn,
    nsm,
    an,
    en,
    et,
    es,
    cs,
    ws,
    s,
    b,
    on,
    lri,
    rli,
    fsi,
    pdi,
    lre,
    rle,
    lro,
    rlo,
    pdf,

    /// The name as the property files and `BidiTest.txt` write it.
    pub fn name(self: BidiClass) []const u8 {
        return switch (self) {
            .l => "L",
            .r => "R",
            .al => "AL",
            .bn => "BN",
            .nsm => "NSM",
            .an => "AN",
            .en => "EN",
            .et => "ET",
            .es => "ES",
            .cs => "CS",
            .ws => "WS",
            .s => "S",
            .b => "B",
            .on => "ON",
            .lri => "LRI",
            .rli => "RLI",
            .fsi => "FSI",
            .pdi => "PDI",
            .lre => "LRE",
            .rle => "RLE",
            .lro => "LRO",
            .rlo => "RLO",
            .pdf => "PDF",
        };
    }

    /// Parses a property value name as it appears in `BidiTest.txt`.
    pub fn parseName(token: []const u8) ?BidiClass {
        inline for (std.meta.fields(BidiClass)) |field| {
            const candidate: BidiClass = @enumFromInt(field.value);
            if (std.mem.eql(u8, token, candidate.name())) return candidate;
        }
        return null;
    }

    /// A code point whose `Bidi_Class` is this value.
    ///
    /// Each is the canonical character for its class in UCD terms: an ASCII
    /// digit for `EN`, the Arabic-Indic zero for `AN`, a letter of the script
    /// that gives the class its name, and the explicit formatting characters
    /// the standard reserves for the format classes. `Table.classOf` proves
    /// every one of them.
    pub fn representative(self: BidiClass) u32 {
        return switch (self) {
            .l => 0x0061, // LATIN SMALL LETTER A
            .r => 0x05D0, // HEBREW LETTER ALEF
            .al => 0x0627, // ARABIC LETTER ALEF
            .bn => 0x00AD, // SOFT HYPHEN
            .nsm => 0x0300, // COMBINING GRAVE ACCENT
            .an => 0x0660, // ARABIC-INDIC DIGIT ZERO
            .en => 0x0030, // DIGIT ZERO
            .et => 0x0023, // NUMBER SIGN
            .es => 0x002B, // PLUS SIGN
            .cs => 0x002C, // COMMA
            .ws => 0x0020, // SPACE
            .s => 0x0009, // CHARACTER TABULATION
            .b => 0x000A, // LINE FEED
            .on => 0x0021, // EXCLAMATION MARK
            .lri => 0x2066, // LEFT-TO-RIGHT ISOLATE
            .rli => 0x2067, // RIGHT-TO-LEFT ISOLATE
            .fsi => 0x2068, // FIRST STRONG ISOLATE
            .pdi => 0x2069, // POP DIRECTIONAL ISOLATE
            .lre => 0x202A, // LEFT-TO-RIGHT EMBEDDING
            .rle => 0x202B, // RIGHT-TO-LEFT EMBEDDING
            .lro => 0x202D, // LEFT-TO-RIGHT OVERRIDE
            .rlo => 0x202E, // RIGHT-TO-LEFT OVERRIDE
            .pdf => 0x202C, // POP DIRECTIONAL FORMATTING
        };
    }
};

/// One line of `DerivedBidiClass.txt`.
pub const Range = struct {
    first: u32,
    last: u32,
    class: BidiClass,
};

pub const Error = error{MalformedLine} || std.mem.Allocator.Error;

/// The ranges of `DerivedBidiClass.txt`, in the order the file lists them.
///
/// The file groups its ranges by class rather than sorting them by code point,
/// so a lookup is a scan. That is fine for the one use this table has — 23
/// lookups, once — and it removes any assumption about the file's ordering.
pub const Table = struct {
    allocator: std.mem.Allocator,
    ranges: []Range,

    /// Parses the property file. Lines that are not `<range> ; <class>` after
    /// the comment is stripped are ignored, which is what makes the file's own
    /// documentation and its `@missing` lines harmless.
    pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) Error!Table {
        var ranges: std.ArrayList(Range) = .empty;
        errdefer ranges.deinit(allocator);

        var lines = std.mem.splitScalar(u8, bytes, '\n');
        while (lines.next()) |raw_line| {
            const line = stripComment(raw_line);
            if (line.len == 0) continue;

            var fields = std.mem.splitScalar(u8, line, ';');
            const range_field = fields.next() orelse continue;
            const class_field = fields.next() orelse continue;

            const range = parseRange(range_field) orelse continue;
            const class = BidiClass.parseName(std.mem.trim(u8, class_field, " \t")) orelse continue;
            try ranges.append(allocator, .{ .first = range.first, .last = range.last, .class = class });
        }

        return .{ .allocator = allocator, .ranges = try ranges.toOwnedSlice(allocator) };
    }

    pub fn deinit(self: *Table) void {
        self.allocator.free(self.ranges);
        self.* = undefined;
    }

    /// The `Bidi_Class` of `codepoint`, or `null` when the file does not cover
    /// it.
    pub fn classOf(self: *const Table, codepoint: u32) ?BidiClass {
        for (self.ranges) |range| {
            if (codepoint >= range.first and codepoint <= range.last) return range.class;
        }
        return null;
    }

    /// Checks every representative against the file, returning the first value
    /// whose representative does not have the class it stands for.
    pub fn firstInconsistentRepresentative(self: *const Table) ?BidiClass {
        inline for (std.meta.fields(BidiClass)) |field| {
            const class: BidiClass = @enumFromInt(field.value);
            const found = self.classOf(class.representative()) orelse return class;
            if (found != class) return class;
        }
        return null;
    }
};

fn stripComment(line: []const u8) []const u8 {
    const without_comment = if (std.mem.findScalar(u8, line, '#')) |hash| line[0..hash] else line;
    return std.mem.trim(u8, without_comment, " \t\r");
}

fn parseRange(field: []const u8) ?struct { first: u32, last: u32 } {
    const text = std.mem.trim(u8, field, " \t");
    if (std.mem.find(u8, text, "..")) |dots| {
        const first = std.fmt.parseInt(u32, text[0..dots], 16) catch return null;
        const last = std.fmt.parseInt(u32, text[dots + 2 ..], 16) catch return null;
        if (last < first) return null;
        return .{ .first = first, .last = last };
    }
    const only = std.fmt.parseInt(u32, text, 16) catch return null;
    return .{ .first = only, .last = only };
}
