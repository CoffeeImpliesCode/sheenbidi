// SPDX-License-Identifier: Apache-2.0
//
//! Exercises calls before and after provider loading in child-process modes.
//! Pre-load and linked-load calls must panic; after-load requires a provider.

const std = @import("std");
const sheenbidi = @import("sheenbidi");

/// What this program was asked to do.
const Mode = enum { pre_load, after_load, linked_load };

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const mode: Mode = if (args.len < 2)
        .pre_load
    else if (std.mem.eql(u8, args[1], "pre-load"))
        .pre_load
    else if (std.mem.eql(u8, args[1], "after-load"))
        .after_load
    else if (std.mem.eql(u8, args[1], "linked-load"))
        .linked_load
    else {
        std.debug.print("misuse: unknown mode '{s}'\n", .{args[1]});
        return error.UnknownMode;
    };

    switch (mode) {
        .pre_load => {
            // No load; the routed call must panic.
            report("calling versionString() with no provider loaded");
            const version = sheenbidi.versionString();
            std.debug.print("misuse: returned \"{s}\"\n", .{version});
        },
        .after_load => {
            const path = if (args.len > 2) args[2] else "";
            if (path.len == 0) {
                std.debug.print("misuse: after-load needs the provider path\n", .{});
                return error.MissingProvider;
            }
            report("loading a provider");
            try sheenbidi.load(.{ .path = path });
            report("calling versionString() with the provider loaded");
            const version = sheenbidi.versionString();
            std.debug.print("misuse: returned \"{s}\"\n", .{version});
        },
        .linked_load => {
            // A linked build has no dynamic table, so this call must fail.
            report("calling load() on a linked build");
            sheenbidi.load(.{ .path = "unused" }) catch |err| {
                std.debug.print("misuse: load reported {t}\n", .{err});
                return;
            };
            std.debug.print("misuse: load returned without an error\n", .{});
        },
    }
}

fn report(what: []const u8) void {
    std.debug.print("misuse: {s}\n", .{what});
}
