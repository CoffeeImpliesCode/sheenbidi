// SPDX-License-Identifier: Apache-2.0
//
//! Builds runtime-loaded modules from a target's C translation.
//! The dispatch owns one loader instance; do not link the C archive into it.
const std = @import("std");

/// Prefix for `runtime/sync.c` symbols; keep it in sync with `runtime/library.zig`.
/// Use a distinct prefix for each SDK instance in one process.
const sync_prefix = "sheenbidi_rt";

/// C-library externs kept direct when present in the translated header.
/// Use a conservative superset: absent names are ignored; missing names get routed.
const libc_noise =
    \\memcpy,memmove,memset,memcmp,memchr,memccpy,mempcpy,bzero,bcopy,bcmp,
    \\strlen,strcmp,strncmp,strcpy,strncpy,stpcpy,strcat,strncat,strchr,strrchr,
    \\strstr,strdup,strndup,strcasecmp,strncasecmp,strspn,strcspn,strpbrk,strtok,
    \\malloc,calloc,realloc,reallocarray,free,aligned_alloc,abort,exit,_exit,
    \\atexit,qsort,bsearch,abs,labs,llabs,
    \\wcslen,wcscmp,wcsncmp,wcscpy,wcsncpy,wcschr,wcsrchr,wcsstr,wcsdup,
    \\__mb_cur_max,__ctype_get_mb_cur_max,mbrlen,mbrtowc,wcrtomb,btowc,wctob,
    \\_errno,__errno_location,__stack_chk_fail,__assert_fail,__mingw_get_crt_info,__prefetch
;

/// Optional exports; none are declared in this stable configuration.
const provider_optional = "";

/// Exports excluded from load-time requirements; none in this configuration.
const provider_excluded = "";

/// Core module exposing the same loader types in linked and runtime builds.
/// Only runtime loading requires its platform code.
pub fn createCoreModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("runtime/loader.zig"),
        .target = target,
        .optimize = optimize,
        // Unix loading needs libc's dynamic-loader symbols.
        .link_libc = true,
    });
}

/// Creates the runtime-loaded C module for a target's translation.
/// The dispatch uses that target's actual translated header.
pub fn createModule(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const core = createCoreModule(b, target, optimize);

    const library = b.createModule(.{
        .root_source_file = b.path("runtime/library.zig"),
        .target = target,
        .optimize = optimize,
    });
    library.addImport("rt", core);

    return createDispatchModule(b, translate, target, optimize, core, library);
}

/// What one generator run writes: the dispatch, and the translation it reads.
const GeneratedSources = struct {
    native: std.Build.LazyPath,
    dispatch: std.Build.LazyPath,
};

fn createDispatchModule(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    core: *std.Build.Module,
    library: *std.Build.Module,
) *std.Build.Module {
    const sources = generateDispatch(b, translate, target);

    const dispatch = b.createModule(.{
        .root_source_file = sources.dispatch,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    dispatch.addImport("rt", core);
    dispatch.addImport("library", library);

    // Share translated types and route nested aliases through the dispatch.
    const native = b.createModule(.{
        .root_source_file = sources.native,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    native.addImport("c_routed", dispatch);
    dispatch.addImport("c_native", native);
    dispatch.addCSourceFiles(.{
        .files = &.{"runtime/sync.c"},
        .flags = &.{b.fmt("-DRT_SYNC_PREFIX={s}", .{sync_prefix})},
        .language = .c,
    });
    return dispatch;
}

/// Runs the host generator against this target's actual translation.
/// Different translated outputs produce different dispatch modules.
fn generateDispatch(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
) GeneratedSources {
    const generator = b.addExecutable(.{
        .name = b.fmt("sheenbidi-runtime-generate-{s}", .{
            target.result.zigTriple(b.allocator) catch @panic("unspellable target"),
        }),
        .root_module = b.createModule(.{
            .root_source_file = b.path("runtime/generate.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });

    const run = b.addRunArtifact(generator);
    run.addArg("--library");
    run.addArg("sheenbidi");
    run.addArg("--translate");
    run.addFileArg(translate.getOutput());
    if (libc_noise.len != 0) {
        run.addArg("--noise");
        run.addArg(libc_noise);
    }
    if (provider_optional.len != 0) {
        run.addArg("--optional");
        run.addArg(provider_optional);
    }
    if (provider_excluded.len != 0) {
        run.addArg("--exclude");
        run.addArg(provider_excluded);
    }
    run.addArg("--native-output");
    const native_source = run.addOutputFileArg("native.zig");
    run.addArg("--output");
    const dispatch_source = run.addOutputFileArg("dispatch.zig");
    return .{ .native = native_source, .dispatch = dispatch_source };
}
