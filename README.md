# sheenbidi — SheenBidi 3.0.0, built from upstream's own C for Zig 0.16.0

This is a fork of **SheenBidi 3.0.0** — upstream's own C implementation of the
Unicode Bidirectional Algorithm (UAX #9), pinned at tag `v3.0.0`, commit
`cfe430e7375a7845b679adae9d51dac6deaa8858` from
`https://github.com/Tehreer/SheenBidi.git` — compiled from the C sources carried
in this repository and published as a Zig package. The algorithm is not
reimplemented: no UCD table is regenerated, no upstream file is patched, and
nothing is downloaded at build time. The only dependency is a C compiler and
libc, and `build.zig.zon` declares no Zig dependencies.

Where things are written down, and this README deliberately does not repeat them:

| Document | What it holds |
|---|---|
| [`README.zig.md`](README.zig.md) | **the Zig interface**: the facade, the raw `c` route, lifetimes, the allocator protocol, bounds and base-level rules, the examples, the test approach, and the authoritative gate matrix |
| [`README.upstream.md`](README.upstream.md) | upstream's README, byte for byte, including the Apache-2.0 grant it carries |
| [`UPSTREAM.md`](UPSTREAM.md) | what the fork is a fork of: the pin, the archive digest, what is compiled, what is shipped, how to re-sync |
| [`NOTICE.md`](NOTICE.md) | attribution, the three-way licence split, every file this fork adds or edits, the installed closure, the patent-grant termination clause |
| [`FORK-LICENSE.md`](FORK-LICENSE.md) | the owner authorization and the actual grant for the fork-authored files |
| [`UPSTREAM.sha256`](UPSTREAM.sha256) | 218 SHA-256 records covering every upstream file this package ships |
| [`CHANGELOG.md`](CHANGELOG.md) | the numbered, dated history of fork-only changes |

## 1. Deviations from upstream's native source

**None.**

Not one upstream `.c`, `.h`, `.txt`, build file or licence text is modified.
`UPSTREAM.sha256` records the SHA-256 of all 218 upstream files this package
ships, and `sha256sum -c UPSTREAM.sha256` is the check that keeps it that way.
Three non-source facts belong here anyway, because "no source deviation" is a
claim someone will want to audit against something:

* **One upstream file is edited, by appending only:** `.gitignore`. Upstream's 27
  lines are kept verbatim; the fork appends its own `## Zig build output`
  entries. It is excluded from the integrity record precisely because it is not
  byte-identical to upstream any more.
* **One upstream file moved, with no byte changed:** upstream's README was this
  package's `README.md` and is preserved verbatim as `README.upstream.md`
  (`sha256 34376a69…ae1c8`, the digest the integrity record carried before the
  move). `README.md` is now this fork's document. Citations of upstream's README
  by line range moved with the bytes, so `README.upstream.md:169-184` is still
  the licence grant and `:171` is still the copyright line.
* **Nothing upstream is compiled that upstream would not compile.** The build
  compiles upstream's unity translation unit and nothing else; it never runs
  upstream's CMake, meson or Make, and it never runs upstream's generator.

## 2. Deviations from upstream's native build

Upstream ships three build systems (CMake, meson, Make). This package replaces
them with one Zig build and states every C decision it makes:

| Decision | What this package does | Why |
|---|---|---|
| Translation units | one: `Source/SheenBidi.c`, upstream's own unity file, which `#include`s all 32 checked-in `.c` units | it is upstream's default (`option(SB_CONFIG_UNITY … ON)`, `unity_mode = enabled`), and a one-entry list cannot silently gain or lose a unit |
| C dialect | `-std=c90` | all three of upstream's build systems ask for C90, and `Source/API/SBBase.h` and `Source/Core/ThreadLocalStorage.h` pick their atomics and TLS backend from `__STDC_VERSION__`; pinning the dialect keeps that decision identical on every target |
| Experimental text API | **compiled out** — `SB_CONFIG_EXPERIMENTAL_TEXT_API` is not defined | it is upstream's shipped default (`SBConfig.h:39` ships it commented out) and the owner did not select it. See [what is absent](#what-is-absent-in-the-selected-configuration), because "absent" here is more specific than "off" |
| Non-atomic fallback | `SB_CONFIG_ALLOW_NON_ATOMIC_FALLBACK` **not** defined | forcing it on a threaded target would let a data race compile cleanly |
| Scratch memory | `SB_CONFIG_DISABLE_SCRATCH_MEMORY` not defined, so the default allocator's scratch is live: `SB_CONFIG_SCRATCH_BUFFER_SIZE` 8192 and `SB_CONFIG_SCRATCH_POOL_SIZE` 3, both set by `SBConfig.h` itself | upstream's default, and it is part of what a caller may observe |
| System library | off by default; `-fsys=sheenbidi` selects an installed one, and only for a target this machine is | a distro SheenBidi is unlikely to be the 3.0.0 this manifest pins, and translating one release's header against another release's library is the silent-wrong-answer failure this package exists to avoid. **This mode has never been gated here and no run of it is claimed**. The graph resolves the host before it dispatches, so `-fsys=sheenbidi` with a foreign `-Dtarget` stops at configure time with a named message instead of binding a library installed on this machine to a target this machine is not (`build.zig:762-770`, `:1069-1073`); that guard is **applied and not yet re-gated** — see [§3](#3-build-run-and-test-matrix) |
| Delivery | static by default, exactly as before; `-Dlinkage=static|dynamic` selects the artifact, and `zig build install` now installs a complete closure: library, all 23 public headers, the licence and provenance documents, and the Unicode data files | added by this migration. Static means a static library artifact, not a wholly static executable: SheenBidi calls `malloc`, `free`, `memcpy` and `memmove`, so a consumer needs the platform C runtime either way |
| Runtime loading | `-Druntime=true` builds the facade against a generated dispatch and drops only the link; the artifact is still compiled and installed, and `bin/misuse` is installed in every configuration | added by this migration. `-Dlinkage` and `-Druntime` are orthogonal: all four pairings are real configurations, `-Druntime` never changes what is installed and `-Dlinkage` never changes what the facade is bound to. The ABI a loaded image must satisfy is [§4](#4-runtime-and-native-abi), and the loader's own contract is in [`README.zig.md`](README.zig.md#runtime-loading-and-the-abi-it-needs). **A successful load is observed** — eight `-Druntime=true` gates across both linkages and all four modes exited 0 on 2026-10-04 with `SHEENBIDI_PROVIDER` set; the `bin/misuse` observations it installs are not |

**The DLL macros are part of that delivery choice.** `-Dlinkage=dynamic`
defines `SB_CONFIG_DLL_EXPORT` on the C compile line and `SB_CONFIG_DLL_IMPORT`
on the translation line — upstream's own rule for a DLL build
(`CMakeLists.txt:123-127`), keyed to the artifact kind rather than to the
target, because `SB_PUBLIC` expands to `__declspec(dllexport)` /
`__declspec(dllimport)` only under `_WIN32` (`Headers/SheenBidi/SBBase.h:30-42`)
and is empty everywhere else. The two lines never carry the same macro, and
`zig/translate.h` defines no `SB_CONFIG_*`, so each is defined exactly once and
on exactly one command line. Under the default `static`, neither is defined and
a consumer of the installed headers needs no define.

**What a shared object actually exports.** In unity mode every implementation
unit is `SB_INTERNAL`, which is `static`, so the external set of
`libSheenBidi.so` is exactly the `SB_PUBLIC` functions. There is no variadic
entry point and no exported data symbol anywhere in the public C surface. One
global is not `static` — `_SBLogPosition` in `Source/API/SBLog.h` — but it is
inside `#ifdef SB_CONFIG_LOG`, which this configuration never defines, so it
contributes nothing.

**Dated history.** The full, numbered history of these decisions, each with its
date, its status and the receipt that observed it, is
[`CHANGELOG.md`](CHANGELOG.md) — entries 1–19 are the package as it stood before
this migration; entries 20 and later are this migration. Nothing in this README
is a second, newer version of that history.

## 3. Build, run and test matrix

**The authoritative matrix is [`README.zig.md` § Verification
status](README.zig.md#verification-status).** It is the driver's table, it names
the receipt behind every row, and nothing outside it is claimed as a result.
What follows is the shape of it, with the dates kept explicit so that a
historical result is never read as a current one.

### Observed before this migration (2026-10-02 and earlier)

Historical evidence about the package as it stood then, for the configurations
that still exist. Each row is a real driver run with a real receipt; the receipts
and their exact contents are in the linked table.

| Gate | Command | Observed, then |
|---|---|---|
| upstream byte integrity | `sha256sum -c UPSTREAM.sha256` | green, exit 0, 218 records |
| install | `zig build`, `zig build --prefix <dir>` | green, 6/6 steps, on two hosts |
| installed C surface | `zig cc -I <dir>/include <dir>/lib/libSheenBidi.a …` then run it | green, 58 `ok` lines, no `FAIL` |
| tests | `zig build test` (Debug **and** ReleaseSafe in one command) | green, 19 tests per mode, both UAX #9 replays in full |
| smoke | `zig build smoke` | green, Debug and ReleaseSafe |
| consumer | `cd consumer && zig build run` | green, from this tree and from a fetched copy |
| six-target compile check | `zig build check -Dtarget=<triple>` | green for all six, compile-only |
| full matrix | `cross-test --jobs 2 --build-jobs 2 --build-timeout 3600` | exit 0 over all 53 published targets: **20 pass, 33 build_only, 0 fail** |

### Observed since this migration (2026-10-04)

Sixteen gates ran on 2026-10-04 between 15:09 and 15:20 UTC, all exit 0, each
with a receipt under
`…/contract-physics-lua/current-native-evidence/sheenbidi-current-{native,loaded}-{static,dynamic}-{Debug,ReleaseSafe,ReleaseFast,ReleaseSmall}-…json`.
Every one is the same command shape: `zig build test smoke install` with
`-Druntime=<false|true>`, `-Dlinkage=<static|dynamic>`, `-Doptimize=<mode>`,
`-j8` and `--summary all`, against a scratch `--prefix`.

What they establish, from their own printed output:

* **44/44 tests passed**, printed as `run test 22 pass (22 total)` twice per
  invocation, once for Debug and once for ReleaseSafe, under `51/51 steps
  succeeded` (native) or `52/52 steps succeeded` (loaded). The test count is 22
  per mode, not the 19 the pre-migration rows below record.
* **`smoke` ran and asserted**, closing on `every printed answer matched the
  published expectation` in both the `linked` and the `loaded` configuration.
* **`install` ran** and its step summary names `install generated to
  pkgconfig/SheenBidi.pc` — the capitalised name — in all sixteen.
* **The runtime route is exercised, not merely described.** The eight loaded
  receipts carry `-Druntime=true` and set `SHEENBIDI_PROVIDER` to a separately
  built `libSheenBidi.so`, and each prints `configuration: loaded`.

Two prefix installs from those runs are readable on disk, and both contain
`lib/pkgconfig/SheenBidi.pc` and **nothing else** in that directory:
`sheenbidi-static/lib/pkgconfig/SheenBidi.pc` ends `Cflags: -I"${includedir}"`,
and `sheenbidi-shared/lib/pkgconfig/SheenBidi.pc` ends
`Cflags: -I"${includedir}" -DSB_CONFIG_DLL_IMPORT`. Both write
`prefix=${pcfiledir}/../..`, `Libs: -L"${libdir}" -lSheenBidi` and
`Name: SheenBidi`. That is the corrected `.pc` story below, observed rather than
inferred.

What these sixteen do **not** establish, and is not claimed anywhere above: no
`bin/misuse` observation ran (the receipt records `install misuse`, not a run of
it), so `pre-load`/`after-load`/`linked-load`, retry, idempotence and
provider-change remain unexercised; and they ran before the run-step
`has_side_effects` change, which is `PENDING-VERIFICATION` and needs its own
focused proof.

### Observed in the current source epoch (2026-10-04 late, 2026-10-05)

Four driver rounds ran against the tree as it stands, each under its own epoch
so that a receipt from an earlier date is never read as one of these. The
authoritative table is still
[`README.zig.md` § Verification status](README.zig.md#verification-status);
this is the current headline of it.

| Gate | Epoch and receipt | Observed now |
|---|---|---|
| full 53-platform `cross-test` matrix | `20261004T221720228710Z-45046`, `sheenbidi-53-target-8.json` | exit 0 over all 53 published targets at `--jobs 8 --build-jobs 8`: **20 pass, 33 `build_only`, 0 fail**, with `source_unchanged: true` and `jobs_honoured: true`. Each of the twenty reports `run=pass tests=44`; each of the thirty-three reports `run=unavailable reason=runtime_unavailable`. **Twenty runtime passes over fifty-three targets is not fifty-three passes**, and the thirty-three are compile evidence |
| six-target compile baseline | `20261005T014547Z-797a73f2`, `baseline-sheenbidi-check` | exit 0, `failed: false`, `Build Summary: 31/31 steps succeeded`, with all six triples seen and six step lines each. The receipt carries `runtime_pass_claimed: false` and an empty `test_pass_lines`: **a compile-only row derives no runtime result under any exit code** |
| native eight-cell wave | `20261004T233628757747Z-69351` | **8 pass** — both linkages across all four optimize modes, each cell one `zig build test smoke install -Druntime=false -j8 --summary all`, exit 0, `51/51 steps succeeded`, `44/44 tests passed`, no skipped test |
| own-loaded eight-cell wave | `20261004T232823091897Z-23133` | **8 pass** — the same eight cells with `-Druntime=true` and `SHEENBIDI_PROVIDER` set to this SDK's own source-built `libSheenBidi.so`, exit 0, `52/52 steps succeeded`, `44/44 tests passed`, no skipped test |

`44/44` is twenty-two tests in Debug and the same twenty-two in ReleaseSafe,
from one `zig build test`; it is never forty-four in a single mode. That is the
count the current tree prints. `38/38`, and the `19 per mode` the pre-migration
rows record, are the earlier figures and are correct for their own date.

**Two items an earlier diagnostic wave raised, and they are not the same
item.** The build graph now resolves the host before it dispatches, so
`-fsys=sheenbidi` is refused for a foreign `-Dtarget` rather than binding a
library installed on this machine to a target this machine is not
(`build.zig:762-770`, `:1069-1073`). That guard is a real change in this
package's own graph, and it is **applied** — but **no receipt in this section
was taken after it landed**, so it is not yet re-gated. Separately, the same
wave reported the *path of the selected header* incorrectly. That is a gap in
the observing tool, not a defect in this package: this package's own semantic
cells exited 0, and nothing here presents it as an SDK failure. One observer
correction, now frozen, covers it together with the SheenBidi relative-header
handling and the nested diagnostic and `INSTALL` observer handling; no run has
happened since that correction was frozen, so no result of it is claimed or
predicted here.

### Still pending verification

| Item | State |
|---|---|
| the 218-record integrity check after the `README.md` → `README.upstream.md` rename | **PENDING-VERIFICATION** — the record was updated to follow the rename; the check itself has not been re-run |
| the installed C surface against the new closure | **PENDING-VERIFICATION** — the older green receipt is pre-migration and is labelled as such above |
| `zig build check` on the six targets, and the full 53-platform matrix | **OBSERVED** in the current source epoch — the compile-only baseline and the 53-target sweep are the two rows above, each with its own epoch and count. Neither is a full-suite runtime pass: the baseline ran nothing at all, and 33 of the 53 cells remain `build_only` |
| `bin/misuse`: the three observations per runtime cell, the process-lifetime table, explicit path or named-system selection, no fallback, atomic publication, explicit retry, and the pre-initialization check in every optimize mode | **PENDING-VERIFICATION**. `zig build test -Druntime=true` needs `SHEENBIDI_PROVIDER` or `--provider <path>` and stops naming both when neither is set |
| the run-step `has_side_effects` change, which needs a repeated run in one cache to show it executes rather than being served | **PENDING-VERIFICATION** |
| `zig fetch` of the package, the integrity check inside it, and the consumer inside it | **PENDING-VERIFICATION** |
| the canonical devenv shell, and the static and shared Nix derivations with their output dependency records | **PENDING-VERIFICATION** |
| `zig build -fsys=sheenbidi` | **never run**, before this migration or in it, at run time or at compile time |

### Boundaries that are real and are not going away

* No BSD, Darwin, Windows or WASI cell of this package has ever executed
  anything. Those 33 cells compile and link; `build_only` is compile evidence
  and is reported as such, never as a pass.
* `zig build check` never runs anything. A green check is a compile-and-link
  result.
* **No independent external provider was exercised for this package.** The
  external route wave `20261004T232439Z` accepted none: in
  `sheenbidi-index.json` no route carries `counts_as_external_coverage: true`,
  and its coverage block records `external_successes_observed: 0`. The only
  route that succeeded was this SDK's own source-built image, and every
  external candidate was an expected refusal — a library that does not export
  the fifty-one `SB_PUBLIC` functions a provider has to supply. The eight
  loaded cells above are therefore own-provider evidence, and provider
  independence is a boundary here rather than a coverage row.
* `-fsys=sheenbidi` needs an installed SheenBidi 3.0.0 with its own matching
  header, and none is available here.
* Upstream's own C++ suite in `Tests/` is not compiled by this package's build.
  It travels for provenance and for a re-sync diff.

## 4. Runtime and native ABI

If a build dispatches through a loaded native image rather than a linked one —
`-Druntime=true`, the runtime configuration this migration adds — the following
is the ABI it has to satisfy. It is read out of upstream's headers and sources,
not inferred from the fact that symbols resolved.

* **Headers and translation.** The whole public surface is declared by
  `Headers/SheenBidi/SheenBidi.h`, which includes the other 22 public headers.
  The translated declarations are the ABI; nothing is added to them and nothing
  is removed.
* **Scalar widths.** `SBUInteger` is `uintptr_t` and `SBInteger` is `intptr_t`
  (`Headers/SheenBidi/SBBase.h:97-102`), so every offset, length and index
  crosses at the machine-word width of the **target**, not of the provider's
  build host; `SBLLevel`, `SBBidiType`, `SBScript` and `SBGeneralCategory` are
  all `SBUInt8`. A 32-bit provider in a 64-bit process cannot work, and nothing
  in the loader can discover that.
* **Struct layout, and all five cross by pointer.** `SBCodepointSequence`,
  `SBAllocatorProtocol`, `SBRun`, `SBScriptAgent` and `SBMirrorAgent` are passed
  or returned across the boundary by pointer, so their field order and padding
  are part of the contract. None has a configurable field, so a provider built
  from any revision of these headers at this pin agrees with them.
* **All fifty-one public functions, and no data.** Every `SB_PUBLIC` declaration
  `zig/translate.h` reaches in this configuration, with none optional — and not
  one data symbol: the two tables behind the code point queries are internal to
  `Source/Data/`. There is no variadic entry point either, so a dispatch has
  neither to reproduce.
* **Opaque handles and their counts.** `SBAlgorithmRef`, `SBParagraphRef`,
  `SBLineRef`, `SBMirrorLocatorRef`, `SBScriptLocatorRef` and `SBAllocatorRef`
  are handles to objects the provider owns, and retain/release must be a real
  count: the facade hands out one handle per `create` and per `retain`. A handle
  must be created, used and released through **one** image — mixing a loaded copy
  with a linked copy is undefined in both directions.
* **Callback structures.** `SBAllocatorProtocol` is a struct of six function
  pointers (`allocateBlock`, `reallocateBlock`, `deallocateBlock`,
  `allocateScratch`, `resetScratch`, `finalize`), each taking a `void *info`
  context. Struct-of-function-pointers is passed **by pointer**, never by value.
  The header says only `allocateBlock` and `deallocateBlock` are required; the
  implementation calls `reallocateBlock` unconditionally wherever a `List` grows,
  so a custom allocator whose `reallocateBlock` is `NULL` is a null call, not a
  fallback. This is stated from the source, not from the header's own promise.
* **The default allocator is process-global, and its lifetime is the caller's.**
  `SBAllocatorSetDefault` stores into one `static` atomic pointer
  (`Source/API/SBAllocator.c`) and does not retain: the caller keeps the
  allocator alive. Nothing records which allocator an object came from — allocate
  and free each resolve whatever is current *at that moment* — so an object
  created under allocator `A` and released after a swap is freed through `B`.
  The default in force at creation must still be in force at the last release,
  for every object. A custom allocator that implements `allocateScratch` must
  make its scratch per-thread itself: the core resets scratch on the calling
  thread only.
* **Thread-local scratch.** With `SB_CONFIG_DISABLE_SCRATCH_MEMORY` undefined,
  paragraph resolution and line construction request scratch and reset it before
  returning, on the calling thread.
* **What is deliberately *not* required.** Which Unicode revision the provider's
  tables were built from. Nothing in the headers selects one, so two providers
  that agree on the points above can still disagree about a code point introduced
  after the older was built. The conformance fixtures in `Tools/Unicode/` bound
  this package's own answer, not a provider's.
* **What the ABI is not.** A successful symbol lookup and a successful release
  are not evidence that any of the above holds; they are what a broken load looks
  like when it looks fine.

Full detail, with the file and line behind each claim, is in
[`README.zig.md` § Lifetimes](README.zig.md#lifetimes-in-one-place) and
[§ Redirecting the native allocator](README.zig.md#redirecting-the-native-allocator).

## What is absent in the selected configuration

Stated rather than left to be discovered, because the headers in the install make
it look otherwise:

* **The experimental text and attribute API is not in the artifacts.** Seven of
  the 23 installed headers — `SBText.h`, `SBTextConfig.h`, `SBTextIterators.h`,
  `SBTextType.h`, `SBAttributeInfo.h`, `SBAttributeList.h` and
  `SBAttributeRegistry.h` — are entirely inside `#if SB_TEXT_API_SUPPORTED`,
  which `SBBase.h:44-48` keys off `SB_CONFIG_EXPERIMENTAL_TEXT_API`. With that
  macro undefined they declare **nothing**: not a type, not a function. The three
  matching `.c` units compile to no definitions at all, so there are no symbols to
  stub and none are stubbed. A caller who defines the macro against these headers
  gets code that **does not link** against this build, which is the right kind of
  failure; it is not a working API and is not offered as one.
* `SB_CONFIG_LOG` is not defined, so there is no logging surface.
* `SB_CONFIG_DLL_EXPORT` / `SB_CONFIG_DLL_IMPORT` are not defined, so the
  installed headers carry no import/export decoration and a consumer needs no
  define to use them.

## 5. Consumption

### As a Zig package

```zig
// your build.zig.zon
.dependencies = .{
    .sheenbidi = .{ .path = "../sheenbidi" },
},
```

```zig
// your build.zig
const dep = b.dependency("sheenbidi", .{ .target = target, .optimize = optimize });
exe_mod.addImport("sheenbidi", dep.module("sheenbidi"));
```

The module carries its own C artifact, so a dependent names neither
`libSheenBidi.a` nor an include path nor `-lSheenBidi`. A dependent that wants
the C API reaches it as `sheenbidi.c` from inside that module — the same
translated declarations the facade uses, not a second import. The consumer
executable needs `link_libc = true`, because SheenBidi allocates with `malloc`
and reads through the buffer it is handed.

```zig
const std = @import("std");
const sheenbidi = @import("sheenbidi");

// "car means " + three Hebrew letters + "."
const text = "car means \u{05D0}\u{05D1}\u{05D2}.";
const source = sheenbidi.Source.fromUtf8(text);   // borrowed, never copied

var algorithm = try sheenbidi.Algorithm.create(source);
defer algorithm.deinit();

var paragraph = try algorithm.createParagraph(0, source.codeUnits(), .auto_ltr);
defer paragraph.deinit();

var line = try paragraph.createLine(paragraph.offset(), paragraph.length());
defer line.deinit();

for (line.runs()) |run| { /* one run of code units at one level */ }
```

**Borrowing, in one line:** the code units must stay alive and unmodified until
the last object derived from them is released, and every `create`/`retain` is one
handle the caller owes exactly one `deinit` to. The rules, and the four places
upstream's retention is not what a reader would guess, are in
[`README.zig.md` § Lifetimes](README.zig.md#lifetimes-in-one-place).

### Runtime loading

Built with `-Druntime=true`, the module dispatches through a loaded image
instead of a linked one, and the provider is named rather than guessed:

```zig
try sheenbidi.load(.{ .path = "/some/prefix/lib/libSheenBidi.so" });  // or .system = "libSheenBidi.so"
// ordinary module calls from here
```

`.path` names a file, `.system` an explicit name for the platform loader, and
there is no fallback from one to the other. A failed load is not retried for you;
the handle and its request live to the end of the process. `load` exists for this
configuration only — on a linked build calling it is an immediate panic — and
`bin/misuse` from the same install is the one observation a test binary cannot
make for itself: what a call before a successful load does.

### As a C library

`zig build --prefix <dir>` — or the Nix derivation below — gives you:

```
<dir>/include/SheenBidi/*.h    all 23 public headers, unedited
<dir>/lib/libSheenBidi.a       static by default; with -Dlinkage=dynamic,
                              libSheenBidi.so.3.0.0 plus the libSheenBidi.so.3
                              and libSheenBidi.so names, SONAME libSheenBidi.so.3;
                              on Windows bin/SheenBidi.dll and lib/SheenBidi.lib
<dir>/lib/pkgconfig/SheenBidi.pc  pkg-config metadata, from build.zig; its
                              prefix is relative to the file, so it follows
                              whatever --prefix was used
<dir>/share/doc/sheenbidi/     licence, provenance and the Unicode data files
<dir>/bin/misuse               the misuse executable, in every configuration
```

```c
#include <SheenBidi/SheenBidi.h>   /* the aggregate header; the only include */
```

`-I <dir>/include` is the whole search path a C consumer needs, and no
configuration macro is required. Upstream's own worked example is preserved in
[`README.upstream.md`](README.upstream.md) and, in a form this package gates,
in [`README.zig.md` § The installed C contract](README.zig.md#the-installed-c-contract).

### Through Nix

`package.nix` is one source-only derivation with a `linkage` parameter, called
from both `flake.nix` and `devenv.nix` through `pkgs.callPackage`. It imports
nothing from a sibling workspace, names no host path, downloads nothing, and adds
no C flag: the build graph owns the flags, the source list and every installed
file.

```sh
nix build .#static     # $out/lib/libSheenBidi.a
nix build .#shared     # $out/lib/libSheenBidi.so
nix build .#default    # == static, this package's existing policy
```

The build graph installs the library, the 23 public headers, the licence and
provenance documents, the eleven Unicode data files unmodified under
`share/doc/sheenbidi/unicode/` and the pkg-config metadata
`lib/pkgconfig/SheenBidi.pc` — `build.zig`'s own `addPkgConfig` writes that last
one from upstream's `sheenbidi.pc.in`, with `prefix` written as
`${pcfiledir}/../..` relative to the `.pc` file rather than as a CMake-configured
absolute path, so it resolves correctly under any `--prefix`. The derivation adds
no file of its own; an earlier version filled the template into a second,
lower-case `lib/pkgconfig/sheenbidi.pc` that disagreed with the graph's file on
`Cflags`, and that block was removed rather than reconciled, because two writers
for one path is two places to be wrong. No derivation of this package claims a
wholly static closure; see `package.nix` for why, in terms of what SheenBidi
calls.

### Through devenv

```sh
devenv shell                      # or: direnv allow, via .envrc
devenv build outputs.static       # the same package.nix the flake uses
devenv build outputs.shared
```

The shell holds tools — the Zig 0.16.0 compiler and pkg-config — and builds
nothing when it opens; `outputs.static` and `outputs.shared` are lazy and are
evaluated only when a build asks for them. Namespaced `sheenbidi:*` tasks run
this package's own build on demand, and each one changes into this checkout from
a path `devenv.nix` evaluates, so a task runs the same tree whichever directory
devenv was entered from. `build` and `install` take an external `--prefix`
beneath the exported `ZIG_LOCAL_CACHE_DIR` — else `$XDG_CACHE_HOME`, else
`$TMPDIR` — so neither writes `zig-out/` into this NFS checkout, and a caller's
own `--prefix` still overrides that default. State location is the caller's:
supply `TMPDIR`, `DEVENV_HOME`, `XDG_RUNTIME_DIR` and the Zig caches on approved
local scratch before entering the shell. This file hard-codes no mount, account
or store path and erases none of those variables. A `flake.lock` is present in this
working copy, pins `nixpkgs` to the same commit `flake.nix` names, and ships in
`build.zig.zon` `.paths`, so a fetched copy carries the pin its flake declares;
no `devenv.lock` exists here and none is listed. No file of this package writes
either one. The derivation filters both out of the source it hands the build,
which is a separate axis and not a defect: `zig build` never reads a lock file,
so it is the build's input rather than the package's contents. `.gitignore`
deliberately ignores neither.

## Licence

Three sets of terms, in three places, and none of them is implied by another:

* **SheenBidi is `Apache-2.0`.** The text ships verbatim as `LICENSE`; the grant
  is upstream's, at `README.upstream.md:169-184`, under the copyright
  "Copyright (C) 2014-2026 Muhammad Tayyab Akram".
* **The eleven Unicode, Inc. data files in `Tools/Unicode/` are not Apache-2.0.**
  They are Unicode, Inc. data files under the terms their own headers name; ten
  of the eleven carry those terms in their first lines and `UnicodeData.txt`
  names nothing at all. They travel unmodified, are installed unmodified, and are
  neither restated nor relicensed here.
* **This fork's own files are `Apache-2.0` under a direct owner authorization**,
  recorded in [`FORK-LICENSE.md`](FORK-LICENSE.md), chosen to match upstream's
  primary term. No copyright identity is invented, and no fork addition is
  attributed to an upstream author. Earlier documents in this package recorded
  the fork's files as unassigned; that was accurate until the owner authorized a
  grant, and the changelog keeps the earlier record.

`NOTICE.md` carries the per-file inventory, the Apache-2.0 §4 obligations and the
§3 patent-grant termination clause.