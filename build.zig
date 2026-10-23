// SPDX-License-Identifier: Apache-2.0
//! SheenBidi 3.0.0 packaged for Zig 0.16.0.
const std = @import("std");

const manifest = @import("build.zig.zon");

/// Runtime dispatch and reusable linked-loader core builders.
const runtime_graph = @import("runtime/graph.zig");

/// Pinned upstream release and Unicode table revision.
const upstream = struct {
    const canonical_url = "https://github.com/Tehreer/SheenBidi.git";
    const commit = "cfe430e7375a7845b679adae9d51dac6deaa8858";
    const version: std.SemanticVersion = .{ .major = 3, .minor = 0, .patch = 0 };
    /// Unicode revision used by the checked-in tables.
    const unicode_version = "17.0.0";
};

/// Upstream's unity translation unit includes the complete C core.
const core_source = "Source/SheenBidi.c";

/// Public headers, installed under `include/SheenBidi/`.
const public_header_source = "Headers/SheenBidi";
const public_header_dest = "SheenBidi";

/// Upstream's canonical library and pkg-config name.
const library_name = "SheenBidi";

/// Flags for upstream's unity translation unit.
/// C90 keeps upstream's atomic and TLS feature selection deterministic.
/// Unity makes internal implementation symbols static.
const c_flags = [_][]const u8{
    "-std=c90",
    "-DSB_CONFIG_UNITY",
};

/// Destination for an export/import macro.
const DllSide = enum { build, consume };

/// Select the upstream DLL macro for compilation or translation.
/// The macro belongs on the command line that declares the corresponding DLL side.
fn dllMacro(linkage: std.builtin.LinkMode, comptime side: DllSide) ?[]const u8 {
    if (linkage != .dynamic) return null;
    return switch (side) {
        .build => "SB_CONFIG_DLL_EXPORT",
        .consume => "SB_CONFIG_DLL_IMPORT",
    };
}

/// Documentation directory for licensing and provenance files.
const document_dir = "share/doc/sheenbidi";

/// Package license-lookup directory.
const licence_dir = "share/licenses/sheenbidi";

/// Files installed as package documentation.
const installed_documents = [_][]const u8{
    "LICENSE",
    "NOTICE.md",
    "FORK-LICENSE.md",
    "README.md",
    "README.zig.md",
    "README.upstream.md",
    "UPSTREAM.md",
    "UPSTREAM.sha256",
    "CHANGELOG.md",
    "FORK-NOTES.md",
};

/// License and provenance files installed under `share/licenses/sheenbidi/`.
const licence_records = [_][]const u8{
    "LICENSE",
    "README.upstream.md",
    "NOTICE.md",
    "FORK-LICENSE.md",
    "UPSTREAM.md",
    "FORK-NOTES.md",
    "UPSTREAM.sha256",
};

/// Checked-in Unicode data installed under its own terms.
const installed_unicode_data = [_][]const u8{
    "Tools/Unicode/BidiBrackets.txt",
    "Tools/Unicode/BidiCharacterTest.txt",
    "Tools/Unicode/BidiMirroring.txt",
    "Tools/Unicode/BidiTest.txt",
    "Tools/Unicode/DerivedBidiClass.txt",
    "Tools/Unicode/DerivedCoreProperties.txt",
    "Tools/Unicode/DerivedGeneralCategory.txt",
    "Tools/Unicode/PropList.txt",
    "Tools/Unicode/PropertyValueAliases.txt",
    "Tools/Unicode/Scripts.txt",
    "Tools/Unicode/UnicodeData.txt",
};

/// Default cross-target matrix for the compile-only check.
const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

/// The test step always covers Debug and ReleaseSafe.
/// `-Doptimize` does not narrow those test modes.
const test_optimize_modes = [_]std.builtin.OptimizeMode{ .Debug, .ReleaseSafe };

/// One target's facade, C translation and optional library.
const Graph = struct {
    /// Facade module for this target.
    module: *std.Build.Module,
    /// Null when this graph uses a system library.
    artifact: ?*std.Build.Step.Compile,
    /// C translation shared by this target's facades.
    translate_c: *std.Build.Step.TranslateC,
    /// Shared loader core; null when runtime dispatch owns it.
    rt_core: ?*std.Build.Module,
};

/// Build options for one target.
const GraphOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    /// Artifact kind produced by this graph.
    linkage: std.builtin.LinkMode,
    /// Link mode for a system library; separate because system builds produce no artifact.
    system_linkage: std.builtin.LinkMode = .dynamic,
    use_system: bool,
    /// Register public modules once; cross-target checks keep private modules
    /// to avoid name collisions.
    public: bool,
    /// Resolve symbols through the platform loader instead of the linker.
    runtime: bool,
    /// Search-path flavor required by the consuming program.
    loader: Loader = .build_cache,
    /// Reuse another graph to avoid duplicate compilation.
    shared: ?*const Graph = null,
};

/// Build the library and facade for one target.
fn addGraph(b: *std.Build, options: GraphOptions) Graph {
    // Reuse the library when building a second facade flavor.
    const reused = options.shared;
    var artifact: ?*std.Build.Step.Compile = null;

    if (reused) |previous| {
        artifact = previous.artifact;
    } else if (!options.use_system) {
        const c_mod = b.createModule(.{
            .target = options.target,
            .optimize = options.optimize,
            // The core uses libc in both static and shared linkages.
            .link_libc = true,
            // Shared objects need PIC. Do not hide symbols: upstream only
            // annotates exports on Windows.
            .pic = if (options.linkage == .dynamic) true else null,
        });
        c_mod.addIncludePath(b.path("Headers"));
        c_mod.addIncludePath(b.path("Source"));
        c_mod.addCSourceFile(.{
            .file = b.path(core_source),
            .flags = &c_flags,
        });
        // Export decoration belongs on the library build command.
        if (dllMacro(options.linkage, .build)) |macro_name| {
            c_mod.addCMacro(macro_name, "");
        }

        const lib = b.addLibrary(.{
            .name = library_name,
            .linkage = options.linkage,
            .root_module = c_mod,
            // Preserve upstream's shared-library version and SONAME.
            .version = if (options.linkage == .dynamic) upstream.version else null,
        });
        lib.installHeadersDirectory(b.path(public_header_source), public_header_dest, .{});
        artifact = lib;
    }

    const translate_c = if (reused) |previous| previous.translate_c else translate: {
        const translate_c = b.addTranslateC(.{
            .root_source_file = b.path("zig/translate.h"),
            .target = options.target,
            .optimize = options.optimize,
            .link_libc = true,
        });
        if (options.use_system) {
            // Resolve system headers and the library through pkg-config.
            // Match DLL-import decoration and linkage to `system_linkage`.
            if (dllMacro(options.system_linkage, .consume)) |macro_name| {
                translate_c.defineCMacro(macro_name, "1");
            }
            // Runtime dispatch must not link the library before `load`.
            if (!options.runtime) {
                translate_c.linkSystemLibrary(library_name, .{
                    .use_pkg_config = .force,
                    .preferred_link_mode = options.system_linkage,
                });
            }
        } else {
            translate_c.addIncludePath(b.path("Headers"));
            // Match translated DLL-import declarations to this graph's linkage.
            if (dllMacro(options.linkage, .consume)) |macro_name| {
                translate_c.defineCMacro(macro_name, "1");
            }
        }
        break :translate translate_c;
    };
    // Runtime dispatch uses the same translation; only symbol resolution changes.
    // Only linked graphs register a module named `c`.
    const raw = if (options.runtime)
        runtime_graph.createModule(b, translate_c, options.target, options.optimize)
    else if (options.public)
        translate_c.addModule("c")
    else
        translate_c.createModule();

    const facade = if (options.public)
        b.addModule("sheenbidi", .{
            .root_source_file = b.path("zig/root.zig"),
            .target = options.target,
            .optimize = options.optimize,
            .link_libc = true,
        })
    else
        b.createModule(.{
            .root_source_file = b.path("zig/root.zig"),
            .target = options.target,
            .optimize = options.optimize,
            .link_libc = true,
        });
    facade.addImport("c", raw);
    var rt_core: ?*std.Build.Module = null;
    if (options.runtime) {
        // Runtime dispatch owns the loader core and re-exports its public types.
    } else {
        // Facades for one target share LoadSource and LoadError type identity.
        rt_core = if (reused) |previous|
            previous.rt_core.?
        else
            runtime_graph.createCoreModule(b, options.target, options.optimize);
        facade.addImport("rt", rt_core.?);
        if (artifact) |lib| {
            // Published facades use the build-cache search path; installed
            // programs use the install-tree facade.
            linkForLoader(facade, lib, options.target, options.loader);
        } else {
            facade.linkSystemLibrary(library_name, .{
                .use_pkg_config = .force,
                .preferred_link_mode = options.system_linkage,
            });
        }
    }

    return .{
        .module = facade,
        .artifact = artifact,
        .translate_c = translate_c,
        .rt_core = rt_core,
    };
}

/// Return prefix-relative loader paths for installed programs, or null if none
/// is needed. ELF and macOS use origin-relative paths; Windows resolves beside
/// the executable.
fn installedProgramRPath(target: std.Build.ResolvedTarget) ?[]const u8 {
    return switch (target.result.os.tag) {
        .windows, .wasi, .uefi => null,
        else => if (target.result.os.tag.isDarwin()) "@loader_path/../lib" else "$ORIGIN/../lib",
    };
}

/// Choose the shared-library search path for the importing program.
/// Dependents use the build-cache artifact; installed programs need a prefix-relative path.
const Loader = enum {
    /// Installed programs resolve the library relative to the installation prefix.
    install_tree,
    /// Uninstalled programs use the shared library in Zig's build cache.
    build_cache,
};

/// Link a library with the search path required by its consumer.
fn linkForLoader(
    module: *std.Build.Module,
    library: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    loader: Loader,
) void {
    // COFF has no rpath; Windows resolves the DLL beside the executable.
    if (library.linkage != .dynamic or target.result.os.tag == .windows) {
        module.linkLibrary(library);
        return;
    }
    switch (loader) {
        .build_cache => module.linkLibrary(library),
        .install_tree => {
            module.addObjectFile(library.getEmittedBin());
            if (installedProgramRPath(target)) |rpath| module.addRPathSpecial(rpath);
        },
    }
}

/// Only shared libraries with runtime paths need separate facade builds.
fn needsBothLoaders(
    linked: ?*std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
) bool {
    const library = linked orelse return false;
    return library.linkage == .dynamic and target.result.os.tag != .windows;
}

/// Compare the resolved target with the host, including explicitly named targets.
fn isThisMachine(b: *std.Build, target: std.Build.ResolvedTarget) bool {
    const machine = &b.graph.host.result;
    return target.result.cpu.arch == machine.cpu.arch and
        target.result.os.tag == machine.os.tag and
        target.result.abi == machine.abi;
}

/// Add compile-only checks for the C core, facade, tests and example.
/// Test compilation instantiates the facade methods; nothing is run.
/// Options shared across check targets.
const CheckOptions = struct {
    linkage: std.builtin.LinkMode,
    use_system: bool,
    system_linkage: std.builtin.LinkMode,
    runtime: bool,
};

fn addTargetCheck(
    b: *std.Build,
    step: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
    options: CheckOptions,
) void {
    const cross_target = b.resolveTargetQuery(query);
    const graph = addGraph(b, .{
        .target = cross_target,
        .optimize = optimize,
        // Check every matrix target with the requested linkage and runtime mode.
        .linkage = options.linkage,
        .system_linkage = options.system_linkage,
        .use_system = options.use_system,
        .public = false,
        // Build each target's dispatch from its own translation output.
        .runtime = options.runtime,
    });

    const tests_mod = b.createModule(.{
        .root_source_file = b.path("tests.zig"),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
    });
    tests_mod.addImport("sheenbidi", graph.module);
    step.dependOn(&b.addTest(.{ .root_module = tests_mod }).step);

    const smoke_mod = b.createModule(.{
        .root_source_file = b.path("smoke.zig"),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
    });
    smoke_mod.addImport("sheenbidi", graph.module);
    step.dependOn(&b.addExecutable(.{
        .name = "sheenbidi-smoke-cross",
        .root_module = smoke_mod,
    }).step);
}

/// Install pkg-config metadata with a relocatable prefix and the selected DLL flag.
/// The compiled closure uses libc only, so no private library is required.
fn addPkgConfig(b: *std.Build, linkage: std.builtin.LinkMode) void {
    const pc = b.addWriteFiles().add(b.fmt("{s}.pc", .{library_name}), b.fmt(
        \\# Generated by build.zig from upstream's sheenbidi.pc.in. Field names,
        \\# order and values are upstream's; `prefix` is the one value that
        \\# differs, written relative to this file instead of as CMake's
        \\# configured @CMAKE_INSTALL_PREFIX@ so the installed metadata is
        \\# correct wherever --prefix put it. build.zig's addPkgConfig says what
        \\# every other value is and why there is no Libs.private.
        \\prefix=${{pcfiledir}}/../..
        \\exec_prefix=${{prefix}}
        \\libdir=${{prefix}}/lib
        \\includedir=${{prefix}}/include
        \\
        \\Name: {s}
        \\Description: SheenBidi is a lightweight, fast and stable implementation of the Unicode Bidirectional Algorithm.
        \\URL: https://github.com/Tehreer/SheenBidi
        \\Version: {f}
        \\
        \\Requires:
        \\Libs: -L"${{libdir}}" -l{s}
        \\Cflags: -I"${{includedir}}"{s}
        \\
    , .{
        library_name,
        upstream.version,
        library_name,
        // Shared pkg-config entries use upstream's DLL-import macro.
        if (linkage == .dynamic) " -DSB_CONFIG_DLL_IMPORT" else "",
    }));
    const install_pc = b.addInstallFileWithDir(
        pc,
        .lib,
        b.fmt("pkgconfig/{s}.pc", .{library_name}),
    );
    b.getInstallStep().dependOn(&install_pc.step);
}

/// Install the listed licensing and provenance records.
fn installLicenceRecords(b: *std.Build) void {
    for (licence_records) |record| {
        b.installFile(record, b.pathJoin(&.{ licence_dir, std.fs.path.basename(record) }));
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const use_system = b.systemIntegrationOption("sheenbidi", .{
        // Use the system library only by explicit request; version mismatches can fail silently.
        .default = false,
    });
    const linkage_option = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Build the SheenBidi artifact statically or dynamically. Static is this " ++
            "package's existing default and installs libSheenBidi.a; dynamic " ++
            "installs a shared library with upstream's SONAME and compatibility " ++
            "names. In -fsys=sheenbidi mode this graph builds no artifact at " ++
            "all, so there the option names the kind of installed library to " ++
            "bind to instead, and both the linker search mode and the " ++
            "SB_CONFIG_DLL_IMPORT decoration follow it.",
    );
    const linkage = linkage_option orelse @as(std.builtin.LinkMode, .static);
    // System linkage defaults to dynamic because system builds produce no artifact.
    const system_linkage = linkage_option orelse std.builtin.LinkMode.dynamic;
    // Runtime loading is independent of the artifact linkage.
    const runtime = b.option(
        bool,
        "runtime",
        "Resolve SheenBidi's symbols through the platform loader instead of " ++
            "linking the library. Off by default. In this configuration `c` is a " ++
            "dispatch generated from this build's own translation output, the " ++
            "facade is not linked against libSheenBidi, and a caller must call " ++
            "`sheenbidi.load(.{ .path = ... })` before any other call.",
    ) orelse false;

    const package_version = std.SemanticVersion.parse(manifest.version) catch {
        @panic("build.zig.zon: .version is not a semantic version");
    };
    if (package_version.order(upstream.version) != .eq) {
        @panic("build.zig.zon .version no longer matches the pinned upstream release");
    }

    // A system library can only bind to the host target.
    if (use_system and !isThisMachine(b, target)) {
        @panic("-fsys=sheenbidi names a library installed on this machine; it has no meaning for a foreign -Dtarget");
    }

    // Register modules once for package dependents.
    const graph = addGraph(b, .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .system_linkage = system_linkage,
        .use_system = use_system,
        .public = true,
        .runtime = runtime,
    });
    if (graph.artifact) |lib| b.installArtifact(lib);

    // Install licensing and provenance records only when this build produces an artifact.
    if (graph.artifact != null) {
        for (installed_documents) |document| {
            b.installFile(document, b.pathJoin(&.{ document_dir, std.fs.path.basename(document) }));
        }
        const unicode_dir = b.pathJoin(&.{ document_dir, "unicode" });
        for (installed_unicode_data) |data_file| {
            const dest = b.pathJoin(&.{ unicode_dir, std.fs.path.basename(data_file) });
            b.installFile(data_file, dest);
        }

        installLicenceRecords(b);

        // Install the pkg-config record for C consumers.
        addPkgConfig(b, linkage);
    }

    // Install only the misuse program; the smoke example runs from the build cache.
    // Add a private facade only when its install-tree path differs from dependents.
    const install_facade = if (needsBothLoaders(if (runtime) null else graph.artifact, target))
        addGraph(b, .{
            .target = target,
            .optimize = optimize,
            .linkage = linkage,
            .system_linkage = system_linkage,
            .use_system = use_system,
            .public = false,
            .runtime = runtime,
            // This private facade gives the installed program a prefix-relative path.
            .loader = .install_tree,
            // Reuse the library, translation and loader core; only the path differs.
            .shared = &graph,
        }).module
    else
        graph.module;
    const smoke_mod = b.createModule(.{
        .root_source_file = b.path("smoke.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    smoke_mod.addImport("sheenbidi", graph.module);
    const smoke = b.addExecutable(.{
        .name = "sheenbidi-smoke",
        .root_module = smoke_mod,
    });
    b.getInstallStep().dependOn(&smoke.step);

    // Exercise loading before and after success, including linked-build misuse.
    const misuse_mod = b.createModule(.{
        .root_source_file = b.path("runtime/misuse.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    misuse_mod.addImport("sheenbidi", install_facade);
    b.installArtifact(b.addExecutable(.{
        .name = "misuse",
        .root_module = misuse_mod,
    }));

    // Smoke does not depend on install; runtime builds require an explicit provider.
    // A build-time default would name a provider this graph may not produce.
    const smoke_step = b.step("smoke", "Run the deterministic example");
    const smoke_run = b.addRunArtifact(smoke);
    // Always execute the smoke binary instead of reusing a cached run.
    smoke_run.has_side_effects = true;
    if (b.args) |args| smoke_run.addArgs(args);
    smoke_step.dependOn(&smoke_run.step);

    // Keep test blocks in this root so the test step discovers them.
    const test_step = b.step("test", "Build and run the behavioral tests in Debug and ReleaseSafe");
    for (test_optimize_modes) |mode| {
        const mode_graph = addGraph(b, .{
            .target = target,
            .optimize = mode,
            .linkage = linkage,
            .system_linkage = system_linkage,
            .use_system = use_system,
            .public = false,
            .runtime = runtime,
        });
        const tests_mod = b.createModule(.{
            .root_source_file = b.path("tests.zig"),
            .target = target,
            .optimize = mode,
            .link_libc = true,
        });
        tests_mod.addImport("sheenbidi", mode_graph.module);
        const unit = b.addTest(.{ .root_module = tests_mod });
        const unit_run = b.addRunArtifact(unit);
        // Always execute tests; a cached run must not imply assertions passed.
        unit_run.has_side_effects = true;
        test_step.dependOn(&unit_run.step);
    }

    const check_step = b.step(
        "check",
        "Compile the C source, facade, tests and example for every supported target without running them",
    );
    const check_options: CheckOptions = .{
        .linkage = linkage,
        .use_system = use_system,
        .system_linkage = system_linkage,
        .runtime = runtime,
    };
    if (use_system) {
        // System libraries can be checked only for the host target.
        addTargetCheck(b, check_step, target.query, optimize, check_options);
    } else if (!target.query.isNative()) {
        // An explicit target check covers only that target.
        addTargetCheck(b, check_step, target.query, optimize, check_options);
    } else {
        for (check_targets) |query| {
            addTargetCheck(b, check_step, query, optimize, check_options);
        }
    }
}
