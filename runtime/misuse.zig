// SPDX-License-Identifier: Apache-2.0
//
//! The one observation a test cannot make about itself: what a call before a
//! successful load does.
//!
//! A panic stops the process, so it cannot be observed from inside the test
//! binary that caused it. This is a small program instead, built in both
//! configurations and run as a child process; the build runner checks that it
//! stops and that the message names the library, the function and the way out.
//!
//! ```sh
//! zig build                              # build it
//! ./misuse pre-load           # stops: the call arrived before any load
//! ./misuse after-load <path>  # succeeds: the same call after a real load
//! ./misuse linked-load        # stops: a linked build has nothing to load
//! ```
//!
//! `after-load` is the control. Without it, a stop in `pre-load` would be
//! indistinguishable from a build that is broken for some other reason; with
//! it, the same call through the same table succeeds as soon as a provider is
//! loaded, which is the whole difference the test is about.
//!
//! The call chosen is `versionString`, which reaches `SBVersionGetString`
//! (`Headers/SheenBidi/SBVersion.h:37`) and nothing else: no borrowed source, no
//! object to release, no allocator to account for. A stop here is the loader's
//! and nothing else could have caused it.

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
            // No load. The module is unusable, and saying so is the contract.
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
            // In a linked build there is no table, no provider and nothing to
            // resolve, so asking is a programming error rather than an error a
            // caller can handle.
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