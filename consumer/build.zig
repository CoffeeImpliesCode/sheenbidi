// SPDX-License-Identifier: Apache-2.0

const std = @import("std");

/// Builds an external consumer using only the package module.
/// Run with `zig build run` to check the published conformance row.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Forward options so the SDK supplies their defaults.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Link the sheenbidi dependency statically or dynamically. Left unset, " ++
            "the SDK's own default applies.",
    );

    // Forward runtime mode so the SDK keeps one default.
    const runtime = b.option(
        bool,
        "runtime",
        "Build the sheenbidi dependency in its runtime-loading configuration. " ++
            "Left unset, the SDK's own default applies.",
    );

    const dep = b.dependency("sheenbidi", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .runtime = runtime,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // SheenBidi's allocation callbacks require libc.
        .link_libc = true,
    });
    exe_mod.addImport("sheenbidi", dep.module("sheenbidi"));

    const exe = b.addExecutable(.{
        .name = "sheenbidi-consumer",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    // Run the consumer on every invocation.
    run_exe.has_side_effects = true;
    // Forward program arguments to `providerRequest`.
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);

}
