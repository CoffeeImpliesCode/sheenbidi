# Fork notes

## Source changes

No upstream C source, public header, Unicode table, fixture, or C++ test is modified. `.gitignore` is the only edited upstream file.

- `.gitignore` — adds ignore rules for Zig, Nix, and devenv build state.
- `README.upstream.md` — preserves upstream's README under its original name; `README.md` documents this package.
- `zig/translate.h` — gives translate-c the upstream aggregate header so bundled and system builds use the selected headers.
- `zig/root.zig` — adds a typed facade with range checks and ownership errors, and binds mirror loading to the line's own buffer.
- `zig/conformance/bidi_class.zig` — maps Bidi_Class names to code points and checks them against `DerivedBidiClass.txt`.
- `zig/conformance/bidi_test.zig` — parses property-value rows into characters, expected levels, and visual order.
- `zig/conformance/character_test.zig` — parses code-point rows and their expected paragraph and visual results.
- `zig/conformance/level.zig` — shares level and visual-index parsing between both fixture parsers.
- `tests.zig` — embeds and replays the Unicode fixtures from the package root.
- `smoke.zig` — exercises facade calls with a published UAX #9 example.
- `runtime/generate.zig` — generates dispatch code and a patched translation from translate-c output.
- `runtime/graph.zig` — wires target-specific dispatch, translated types, and loader modules.
- `runtime/library.zig` — validates provider data and supplies synchronization callbacks to the loader.
- `runtime/loader.zig` — loads an explicit provider and reports validation and symbol-resolution errors.
- `runtime/sync.c` — implements namespaced mutex, condition-variable, and thread-ID callbacks.
- `runtime/misuse.zig` — exercises calls before loading, after loading, and in linked mode.

## Build graph

- `build.zig` and `build.zig.zon` replace upstream's CMake, Meson, and Make graphs with a Zig package build.
- The build compiles `Source/SheenBidi.c` as a unity translation unit with `-DSB_CONFIG_UNITY` and `-std=c90`; it uses checked-in tables, runs no upstream generators, and leaves the experimental text API disabled.
- `-Dlinkage=static|dynamic` selects the artifact; static is the default. `-fsys=sheenbidi` uses an installed library, and `-Druntime=true` generates dispatch for explicit runtime loading.
- The graph installs headers, relocatable `SheenBidi.pc`, licence and provenance records, and Unicode data. Nix delegates installation to this graph; it does not add a second pkg-config file.
- `test` runs Debug and ReleaseSafe. `check` compiles the facade, tests, example, and C core for six targets without running them.
- `cross-test.profile.sh` sets the standard `test` step, job limit, and timeouts without narrowing the target matrix.

## Platform boundaries

- `-fsys=sheenbidi` resolves a library on the build host and refuses a foreign target; its headers must match the installed library.
- Runtime loading uses `dlopen` on Unix-like targets and `LoadLibraryExW` on Windows; WASI, Emscripten, and freestanding targets have no runtime loader.
- Windows shared builds use export/import macros selected by artifact linkage.
- The six-target `check` matrix is compile-only; it does not establish runtime support for those targets.
