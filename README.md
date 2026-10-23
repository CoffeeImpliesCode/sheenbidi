# SheenBidi for Zig

This package builds SheenBidi 3.0.0, upstream's C implementation of the Unicode
Bidirectional Algorithm (UAX #9), and provides a Zig facade. It pins upstream
tag `v3.0.0` at commit `cfe430e7375a7845b679adae9d51dac6deaa8858`.

## Source deviations from upstream

* No upstream C source, public header, Unicode table, test fixture, or C++ test
  is changed. `UPSTREAM.sha256` records the 218 shipped upstream files.
* `.gitignore` keeps upstream's contents and adds this fork's build-output rules.
* Upstream's README is preserved byte-for-byte as `README.upstream.md`; this
  `README.md` documents the fork.

## Build deviations

Zig 0.16.0's `build.zig` replaces upstream's CMake, Meson, and Make builds. It
compiles upstream's unity file, `Source/SheenBidi.c`, with `-std=c90` and
`-DSB_CONFIG_UNITY`; that file includes the 32 checked-in C units. The build
uses a C compiler and libc, does not run the upstream generator, and leaves the
experimental text API disabled, matching upstream's default.

## Support matrix

Observed on the 2026-10-04/05 source snapshot:

| Published targets | Result |
|---|---|
| 20 of 53 | Executed the suite; each passed 22 Debug and 22 ReleaseSafe tests. |
| 33 of 53 | Compiled and linked only (`build_only`); no binary ran. |

No BSD, Darwin, Windows, or WASI target executed a binary. The runtime-loaded
configurations used this package's own source-built library; no independent
external provider was exercised. System-library mode (`-fsys=sheenbidi`) has
not been tested.

## Consumption

Requires Zig 0.16.0, a C compiler, and libc. Add the package in `build.zig.zon`:

```zig
.dependencies = .{
    .sheenbidi = .{ .path = "../sheenbidi" },
},
```

Import its `sheenbidi` module; it carries the C artifact. The consuming
executable must link libc.

```zig
const dep = b.dependency("sheenbidi", .{ .target = target, .optimize = optimize });
exe_mod.addImport("sheenbidi", dep.module("sheenbidi"));
```

`zig build` installs `libSheenBidi.a` by default. `-Dlinkage=dynamic` selects
`libSheenBidi.so` (versioned `.so.3.0.0` with `.so.3` and `.so` links on Linux),
or `bin/SheenBidi.dll` and `lib/SheenBidi.lib` on Windows. Public headers are
installed under `include/SheenBidi/`; pkg-config metadata is `SheenBidi.pc`.
Set `link_libc = true` for a dependent module that uses SheenBidi.

Build options:

* `-Dlinkage=static|dynamic` selects the installed library artifact; default is
  `static`.
* `-Druntime=true` builds the facade for explicit runtime loading while still
  building and installing the artifact. Call `sheenbidi.load` before using it.
* `-fsys=sheenbidi` uses an installed library and its matching headers instead of
  the bundled source; it is off by default and requires a native target.
* `-Dtarget=<triple>` and `-Doptimize=<mode>` select the target and optimization.

The Nix outputs are `.#static`, `.#shared`, and `.#default` (`static`). For the
facade API, see `README.zig.md`; upstream provenance and file terms are in
`UPSTREAM.md` and `NOTICE.md`.