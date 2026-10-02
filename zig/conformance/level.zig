//! The two list syntaxes the UAX #9 conformance files share.
//!
//! `BidiCharacterTest.txt` and `BidiTest.txt` both describe an expected result
//! as a list of resolved levels — a number, or `x` where rule X9 removed the
//! code point — followed by a list of visual indices. The syntax is identical
//! in both files, so it is parsed once, here.

const std = @import("std");

/// One entry of a resolved-level list: a level, or a code point rule X9
/// removed.
pub const ResolvedLevel = union(enum) {
    level: u8,
    removed,

    /// The level, or `null` when rule X9 removed the code point.
    pub fn value(self: ResolvedLevel) ?u8 {
        return switch (self) {
            .level => |level| level,
            .removed => null,
        };
    }
};

pub const Error = error{MalformedLine} || std.mem.Allocator.Error;

/// Fills `list` from a space-separated level list, reusing its capacity.
pub fn parseLevels(
    list: *std.ArrayList(ResolvedLevel),
    allocator: std.mem.Allocator,
    field: []const u8,
) Error!void {
    list.clearRetainingCapacity();
    var tokens = std.mem.tokenizeAny(u8, field, " \t");
    while (tokens.next()) |token| {
        if (std.mem.eql(u8, token, "x")) {
            try list.append(allocator, .removed);
        } else {
            const level = std.fmt.parseInt(u8, token, 10) catch return Error.MalformedLine;
            try list.append(allocator, .{ .level = level });
        }
    }
}

/// Fills `list` from a space-separated list of decimal indices, reusing its
/// capacity. An empty field produces an empty list, which is what a fixture row
/// whose every character was removed by X9 has.
pub fn parseIndices(
    list: *std.ArrayList(usize),
    allocator: std.mem.Allocator,
    field: []const u8,
) Error!void {
    list.clearRetainingCapacity();
    var tokens = std.mem.tokenizeAny(u8, field, " \t");
    while (tokens.next()) |token| {
        const index = std.fmt.parseInt(usize, token, 10) catch return Error.MalformedLine;
        try list.append(allocator, index);
    }
}

/// How many entries of `levels` survive rule X9.
pub fn survivingCount(levels: []const ResolvedLevel) usize {
    var count: usize = 0;
    for (levels) |level| {
        switch (level) {
            .removed => {},
            .level => count += 1,
        }
    }
    return count;
}
