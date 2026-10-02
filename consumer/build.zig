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

    const dep = b.dependency("sheenbidi", .{
        .target = target,
        .optimize = optimize,
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
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}
