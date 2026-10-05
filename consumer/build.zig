// SPDX-License-Identifier: Apache-2.0

const std = @import("std");

/// A package that consumes `sheenbidi` from outside.
///
/// This exists to prove one thing: that a dependent needs only
/// `dep.module("sheenbidi")` and gets a working, correctly linked library. If
/// the facade module stopped carrying its C artifact, or the translated header
/// stopped matching the C source, this would stop building or stop producing
/// the right run order, and nothing inside the library would notice.
///
/// Run it with `zig build run`. It exits non-zero if any asserted value
/// disagrees with the published conformance row it carries, so it is a check
/// and not a demo.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Forwarded rather than defaulted here. `null` means "the SDK's own
    // default", which is static, and this package deliberately keeps no second
    // copy of that answer to drift away from the one in `build.zig`. Passing
    // `-Dlinkage=dynamic` makes this consumer exercise the shared artifact and
    // the `SB_CONFIG_DLL_IMPORT` decoration that comes with it, which is a
    // different link and a different declaration set from the static one.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Link the sheenbidi dependency statically or dynamically. Left unset, " ++
            "the SDK's own default applies.",
    );

    // The same rule for the runtime route: forwarded, never defaulted, so the
    // SDK's own default stays the single answer. `-Druntime=true` builds the
    // dependency with a dispatch in place of the translated header, and the
    // consumer then has to load a provider before it can call anything.
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
        // SheenBidi's C allocates with malloc and reads through the buffer it
        // is handed, so the executable needs a libc to link against. The
        // library module states this for itself too; repeating it here is what
        // makes this package's own platform boundary visible.
        .link_libc = true,
    });
    exe_mod.addImport("sheenbidi", dep.module("sheenbidi"));

    const exe = b.addExecutable(.{
        .name = "sheenbidi-consumer",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    // Without this, a run whose inputs did not change is served from the run
    // cache and the program never executes, so a second `zig build run` could
    // report the check green without having observed anything.
    run_exe.has_side_effects = true;
    // A runtime-loading build is told which provider to open behind `--`, and
    // those arguments belong to the program rather than to this build, so
    // `zig build run -- --provider <path>` has to reach `providerRequest`.
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);

    // The facade module carries `$ORIGIN/../lib` -- the installed tree's own
    // search path -- and nothing else, so this program, which runs out of this
    // package's build cache where no `lib/` sits beside it, is told where the
    // shared object is. Zig's run step sets no loader search path of its own.
    // See `linkInstalledSibling` in the library's build.zig.
}
