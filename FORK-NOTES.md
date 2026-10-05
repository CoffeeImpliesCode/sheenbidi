# FORK-NOTES — what was decided, and what it cost

This file records the decisions taken while building this Zig package over
SheenBidi 3.0.0, and the lessons that came out of the gates the driver ran. It
is a working document: where a decision has not been gated yet, it says so
rather than predicting the outcome.

**Ownership of the facts here.** Everything with a receipt in it was run by the
driver, not by a worker, and the receipt is named. Everything else is
`SOURCE-CONFIRMED` — read out of a file in this repository — or "not run",
which is the answer wherever a gate has never been executed here. Nothing in
this file is a prediction dressed as a result.

**Where the gate output is.** This file says which decision each gate speaks to
and whether it has spoken yet. The commands, the outputs and the receipts live
in one place — the matrix in
[`README.zig.md`](README.zig.md#verification-status) — and are not restated
here, so a status in this file cannot drift away from the run behind it.

---

## Decisions

### 1. What the integrity record covers, and what it does not

**Decision.** `UPSTREAM.sha256` hashes exactly the upstream-owned entries of
`build.zig.zon` `.paths`: the whole `Headers/` (23 files), `Source/` (75),
`Tools/` (60) and `Tests/` (52) trees, plus the eight root files
`CMakeLists.txt`, `Makefile`, `meson.build`, `meson_options.txt`,
`SheenBidi.cmake.in`, `sheenbidi.pc.in`, `LICENSE` and `README.upstream.md`
— upstream's README, which this fork preserves under that name. **218
records**, one `<hex>  <path>` line each, in `sha256sum` format.

*Why `.paths` and not "the upstream tree".* A record naming files the package
does not ship would fail `sha256sum -c` in a dependent's fetched package, which
is exactly where an integrity record has to keep working. `Source/`,
`Headers/`, `Tools/` and `Tests/` are directory entries in `.paths`, so the
walk that produced the record is the same set a fetch would deliver.

*Why the `Tests/` tree is in it.* Upstream's C++ suite is not compiled by this
package's build. It still ships, and a checksum of a file nothing builds is
still the thing that tells a re-sync whether it changed.

*Why `Tools/` is in it, in full.* It carries the two UAX #9 conformance fixtures
the test root embeds, the UCD 17.0.0 inputs the checked-in `Source/Data` tables
were generated from, and upstream's own generator. A digest of the sources the
build compiles but not of the data the tests replay would leave the most
load-bearing files in the package unpinned.

*Why the Unicode data is not a licence question the record answers.* The eleven
files in `Tools/Unicode/` are Unicode, Inc. data files under the terms their own
headers name, not Apache-2.0 files. `NOTICE.md` records the split and this
record covers the bytes; neither restates the Unicode terms.

*Why `.gitignore` is absent.* It is the one upstream file this fork edits, by
appending, so it is not byte-identical to upstream and its digest would be a
digest of the fork's file presented as upstream's. The append is recorded in
`NOTICE.md` and in `CHANGELOG.md` entry 4 instead.

*Why the record does not hash itself.* A checksum file cannot contain its own
digest.

*Why upstream's CI is absent from it.* `.github/workflows/linux.yml`,
`macos.yml`, `windows.yml`, `.appveyor.yml` and `FUNDING.yml` are carried for
provenance and are deliberately not in `.paths`, so a fetched package does not
receive them and a record over them would break `sha256sum -c` there.

**How the digests were produced.** Each file was read as raw bytes with Bun's
`Bun.file(path).arrayBuffer()` and hashed with `crypto.createHash("sha256")`
from `node:crypto`, on 2026-10-01. No receipt in this package's set reports the
hashing tool's version, so this states the method and claims no version of it.
No shell hashing command and no git command was used. Every record was then
re-derived from the written file with the same method and compared against it —
218 re-derived, 0 mismatches — and the walk reported no symlinks and no
non-regular entries under the four hashed roots, so each digest is of a file's
own bytes and not of a link target's text.

**Status: observed.** The file set and the method are `SOURCE-CONFIRMED`, and
the gate itself has now been run: `sha256sum -c UPSTREAM.sha256` in this
workspace is green — exit 0, 218 records, every line `<path>: OK`, no failure
(`…-sheenbidi-immutable-source-integrity-120.log`). It is wired as well, at
`.github/workflows/verify.yml:57-58`, so CI re-checks the same 218 files on
every push. What the check does *not* establish — that this tree equals upstream
commit `cfe430e7375a7845b679adae9d51dac6deaa8858` — is written out in
[`UPSTREAM.md`](UPSTREAM.md), and closing that link needs a re-fetch.

### 2. `test` runs both optimize modes itself

**Decision.** `build.zig`'s `test` step builds and runs `tests.zig` in Debug and
in ReleaseSafe, as one command, and `-Doptimize` does not narrow it.

**Why.** The two modes are where Zig's own safety checks are live, so a facade
bug that is a `std.debug.assert` in one and silent in the other has to be able
to show up in both. If `-Doptimize` selected the mode, `zig build test` and
`zig build test -Doptimize=ReleaseSafe` would run the same two binaries twice
and the second command would prove nothing extra.

**What it costs.** Each receipt of a `test` run therefore contains two
`run test` results, and a caller cannot tell from the step name which mode a
failure is in. Both red test receipts show the same failure in both modes,
which is the useful answer here anyway; both green ones report
`19 pass (19 total)` twice, so one `38/38 tests passed` summary line is two
runs of nineteen and not thirty-eight distinct tests — and not a count for one
mode either. The two green receipts are two invocations of that one step, not a
Debug receipt and a ReleaseSafe receipt.

The same aggregate reappears in two later places, and neither adds tests: the
2026-10-02 native round prints `38/38` inside one `zig build test smoke install`
graph, and each of the twenty passing cells of the 53-platform matrix prints it
once for its own target. Read as totals, those are twenty cells each running the
same nineteen twice — not a larger suite.

### 3. The test root has to sit at the package root

**Decision.** `tests.zig` and `smoke.zig` are plain files at the package root,
not modules rooted under `zig/`.

**Why.** They `@embedFile` `Tools/Unicode/BidiCharacterTest.txt` and
`Tools/Unicode/BidiTest.txt`, and `@embedFile` resolves against the importing
file's module root directory. A module rooted at `zig/` could not reach
`Tools/Unicode/`; at the package root it can, with no path gymnastics and no
generated include directory. The cost is that the package root is slightly
untidy, which is the right trade for fixtures that must be the real files.

**Also.** `tests.zig` is a real test root and not a wrapper that re-exports
other files: a root with no `test` block of its own would discover no tests and
still exit zero.

### 4. The system-library switch is `-fsys=`, not a `-D` option

**Decision.** `b.systemIntegrationOption("sheenbidi", .{ .default = false })`, so
the user-facing switch is `-fsys=sheenbidi` / `-fno-sys=sheenbidi`.

**Why.** `systemIntegrationOption` writes to the build graph's system-library
map. The build runner fills that map from `-fsys=` and `-fno-sys=`; the `-D`
option map is a different map entirely, so `-Dsystem=sheenbidi` would parse
happily and do nothing at all. Spelling it the other way is the difference
between a mode that works and a mode that looks like it works.

**Why the default is off.** A distro package of SheenBidi is very unlikely to
be the 3.0.0 this manifest pins. In system mode no include path of ours is
added, so the declarations come from the installed header — and an installed
header from a different release translated against a library from this one is
exactly the silent-wrong-answer failure this package exists to prevent. The mode
stays available for a user who has installed a matching release.

**Status: not run, and not approximated.** No installed SheenBidi exists in this
workspace and none is claimed. The installed C surface gate is a different
thing and must not be read as covering this mode: it compiles and runs against
the archive and headers *this* build installed a moment earlier, so no system
library, no `pkg-config` lookup and no release-mismatch question is involved
anywhere in it. What is gated is the bundled install path; what is not is this
mode.

**Host guard.** The switch names a library installed on *this* machine, so
`-fsys=sheenbidi` and a foreign `-Dtarget` are refused together rather than
bound to each other. `std.Target.Query.isNative()` cannot decide that — it is
false for every named target — so the graph resolves the host explicitly and
compares its architecture, operating system and ABI with the requested target's
(`build.zig:762-770`, `:1069-1073`). This is the applied side of
[`CHANGELOG.md`](CHANGELOG.md) entry 34; it is **not yet re-gated**, and no gate
here has looked at it. It changes what the mode *refuses*, not what it
*compiles* when it is used correctly on this machine, which remains ungated as
the paragraph above records.

### 5. An out-of-range request is an error here, where upstream clamps it

**Decision.** `Algorithm.paragraphBoundary`, `Algorithm.createParagraph` and
`Paragraph.createLine` check their ranges in Zig and return
`Error.RangeOutOfBounds` / `Error.EmptyRange`.

**Why.** Upstream normalises with `SBUIntegerNormalizeRange`
(`Source/API/SBBase.c:32`), which clamps a request that runs past the end of the
source, and it computes `offset + length` first — an unsigned expression that
wraps for a large length, and the wrapped sum is what the range test then
compares. The facade checks with subtraction (`length > total - offset`), which
cannot wrap, and reports rather than silently shortening the caller's request.

**Why it is not `std.debug.assert`.** An assert is compiled out in ReleaseFast,
so a public contract guarded by one is a contract that exists only in two of
three modes. These are ordinary comparisons and they survive every optimize
mode.

### 6. One honest error per NULL, and no second allocator

**Decision.** Upstream returns `NULL` and has no error channel. Every argument
is checked first, so the `NULL` that survives is upstream's allocation failure
and nothing else, and it is reported once as `Error.OutOfMemory`.

**Why the taxonomy is this short.** Each error names one condition this package
established and checked itself. An error for a condition nothing in this package
can distinguish would be a name without a cause.

**Why `SBAllocatorSetDefault` stays behind `c`.** It exists, it is translated,
and a caller who wants SheenBidi's allocations in a Zig allocator can install
one. What the facade does not do is expose it: a process-wide default allocator
has no owner here, and a leak oracle for one would have to live outside the test
framework. The facade's own single allocation, `Line.visualOrder`, is explicitly
the caller's.

### 7. `MirrorLocator.loadLine` takes the buffer from the line

**Decision.** `loadLine(line)` passes the line's own buffer; there is no second
argument for the caller to get wrong.

**Why.** `SBMirrorLocatorLoadLine` only accepts a buffer that is
pointer-identical to the one the line was built from
(`Source/API/SBMirrorLocator.c:56`). A load with any other pointer is **ignored
in silence** — not an error, not a `NULL`: the locator simply reports no mirrors.
A signature that took the buffer separately would make that failure reachable by
accident, and the symptom would look exactly like a line with nothing to mirror.
This is the clearest case in the package for a wrapper earning its keep.

### 8. `BaseLevel` is a union, and 125 is the value to be careful with

**Decision.** `BaseLevel` is `union(enum) { auto_ltr, auto_rtl, explicit: Level }`,
and an explicit level above `level_max` is `Error.InvalidBaseLevel`.

**Why not a bare `SBLevel`.** Upstream's own dispatch is
`baseLevel >= SBLevelMax` (`Source/API/SBParagraph.c:255-260`), so `0xFE` and
`0xFF` are not "levels", they are "apply P2 and P3 with this fallback". A bare
`SBLevel` would let a caller pass them by accident and a sentinel by typo.

**The boundary to remember.** An explicit level is used **verbatim** for `0`
through `124`. **`level_max` is `125`, and it is inside the accepted range of
the type but is *not* taken verbatim**: upstream reads it as "not explicit" and
resolves it through P2 and P3, so a right-to-left text at 125 comes back as 1
and a text with no strong character at 125 comes back as 0. The facade passes
125 through unchanged and says so in the type's own doc comment rather than
quietly turning it into an error — upstream accepts it, and the facade's job is
to describe upstream, not to correct it.

### 9. The cross-test settings are a file, and the file carries no licence

**Decision.** `cross-test.profile.sh` sits at the package root with four
variable definitions and nothing else — `CROSS_BUILD_STEP=test`,
`CROSS_BUILD_JOBS=2`, `CROSS_BUILD_TIMEOUT=3600`, `CROSS_TIMEOUT=1800` — and is
listed in `.paths`.

*Why a file at all.* `cross-test` discovers `./cross-test.profile.sh` and
`./test/cross-test.profile.sh` and sources whichever it finds
(`cross-test:618-622`). Without one it still runs, on its own defaults; with
one, the package states its own deadlines and the file travels with the
package. That second half is why it is in `.paths`: a fetched copy is the whole
package, and a harness settings file that only exists in a working tree is a
settings file the package does not have.

*Why no hooks and no matrix.* A profile that defines `cross_build_command` or
`cross_artifact` switches the harness out of its standard Zig-build mode
(`cross-test:645-648`), and one that sets `CROSS_MATRIX` or `TARGETS` narrows
the run (`cross-test:650`, `:676-691`). Both would trade a published 53-platform
gate for a self-chosen subset, which is the one thing this workspace forbids.
Every value here is a default; `cross-test --build-timeout`, `--timeout`,
`--jobs` and `--build-jobs` override it (`cross-test:628-633`).

*Why `CROSS_LIBC_RUNTIMES` is absent.* It is a directory of foreign libc
loaders on the machine running the harness. Putting a host path in a file that
ships inside a package would make the package claim something about one machine.
The harness reads it from the environment, so it can be supplied without the
package knowing anything.

*Licence.* None asserted. This is a fork-authored file like `build.zig` or
`tests.zig`, it sits beside an Apache-2.0 tree, and that grant does not reach
it. `NOTICE.md` now names it in both the prose list and the per-file table.

**Status.** Observed on 2026-10-02. The final sweep of the published 53-target
matrix ran from this directory with the profile sourced and no deadline
override, and exited 0 at **20 pass, 33 build_only, 0 fail**: every cell either
compiled, or compiled and ran all nineteen tests in both modes. The counts, the
per-target receipts and what a `build_only` cell does and does not prove are in
[`README.zig.md`](README.zig.md#the-full-53-platform-matrix-cross-test); §9's
own claim is only that the profile is the right shape, and the sweep supports
that. One consequence of the sweep is still open and is *not* closed by it: the
profile is listed in `.paths`, but no fetched copy has been observed since, so
"a fetched package carries it" remains `SOURCE-CONFIRMED` from the manifest.


---

## Lessons

Each one is written as **condition, symptom, fix, target boundary**, so a later
wave in another directory or against another toolchain version can apply it
without re-deriving it.

### L1 — A method call on a bare struct literal needs parentheses

* **Condition.** Zig 0.16, calling a method on a struct literal written inline
  as the receiver of a call.
* **Symptom.** `tests.zig:555:105: error: expected ',' after argument`, pointing
  at the `.toC()` in `sheenbidi.BaseLevel{ .explicit = 126 }.toC()`. The caret
  sits on the dot, not on the literal, which makes it read like a missing comma
  in the argument list. The whole test step fails to compile in both optimize
  modes, exit 1 (`…-sheenbidi-initial-debug-13.log`).
* **Fix.** `(sheenbidi.BaseLevel{ .explicit = 126 }).toC()`.
* **Boundary.** The Zig 0.16 parser, for any call where the receiver is an
  unparenthesised `struct`/`union`/`enum` literal. It is a parse error, not a
  type error, so it appears before any type reasoning and names the dot.

### L2 — `std.meta.fields` needs `inline for`

* **Condition.** Zig 0.16, iterating `std.meta.fields(SomeEnum)` with a runtime
  `for` and reading `field.value`. `builtin.Type.EnumField.value` is
  `comptime_int` in a struct that "requires comptime because of this field"
  (`lib/std/builtin.zig:731`).
* **Symptom.** `zig/conformance/bidi_class.zig:183:29: error: values of type
  'builtin.Type.EnumField' must be comptime-known, but index value is
  runtime-known`. One of four compilation errors in the test step across both
  modes (`…-sheenbidi-repaired-debug-21.log`).
* **Fix.** `inline for`, which makes each `field` a comptime value. The loop
  then unrolls over a fixed enum, which is what "iterate the fields of an enum"
  has to mean anyway.
* **Boundary.** Zig 0.16's `std.meta.fields`; any loop that wants a field's
  *value* rather than only its name. A loop over the names alone does not need
  it.

### L3 — A translated function returning a struct pointer needs `.*`

* **Condition.** `zig translate-c` publishing a C function declared to return
  `const SomeStruct *`. The result is `[*c]const translate.struct__X`, which is a
  raw C pointer: no field access, no auto-deref.
* **Symptom.** `zig/root.zig:791:34: error: type '[*c]const
  translate.struct__SBScriptAgent' does not support field access`, and the same
  for `[*c]const translate.struct__SBMirrorAgent` at `:856:33`
  (`…-sheenbidi-repaired-debug-21.log`).
* **Fix.** `c.SBScriptLocatorGetAgent(self.ref).*`. Here both pointers come from
  an agent embedded in the locator and are never null, so the pointee is read
  directly — and each site says so, because a `.?` there would be an invented
  error path and a silent null dereference would be a bug.
* **Boundary.** Any translate-c surface where upstream returns a pointer to its
  own internal state rather than a heap object. Check the C declaration for who
  owns the pointee before choosing `.?` over `.`.

### L4 — Pin the C dialect when feature detection branches on it

* **Condition.** A C library whose atomics and TLS backend are selected from
  `__STDC_VERSION__` at compile time — here `Source/API/SBBase.h` and
  `Source/Core/ThreadLocalStorage.h`, which take `<stdatomic.h>` and the C11
  paths at C11 and above and the `__atomic_*` / `__thread` builtins below it.
* **Symptom.** Not observed here, and that is the point: left to the compiler
  default, the same source takes a different branch on different targets, and
  the branches differ in which platform headers they need and in what they
  guarantee about thread safety. It would have shown up as a cross-target
  compile difference with no visible cause.
* **Fix.** `-std=c90` on the one translation unit, which is the level all three
  of upstream's build systems ask for (`Makefile`: `-ansi -pedantic`;
  upstream's `linux.yml`: `CMAKE_C_STANDARD=90` with extensions off, and
  `-Dc_std=c89` for meson).
* **Boundary.** SheenBidi 3.0.0's feature detection, and any target whose Zig C
  front end would otherwise default to C11 or later. Bound to the pinned release:
  a future upstream may add a C11 path it wants by default, and this decision has
  to be re-read then rather than assumed.

### L5 — A fixture that names property values needs its representatives verified

* **Condition.** `BidiTest.txt` states its cases as `Bidi_Class` property values
  and explicitly permits an implementation to "randomly pick characters from
  those with the same Bidi_Class values".
* **Symptom.** Not observed, and again the point: a representative that does not
  have the class it stands for replays a *different* property sequence, and the
  row still passes or fails for a reason that has nothing to do with the
  implementation under test. A conformance suite can be green and wrong.
* **Fix.** One fixed representative per value, and every one of them checked
  against Unicode's own `DerivedBidiClass.txt`, which ships in this repository;
  plus ten anchors that do not depend on the representative table at all, so a
  parser that agreed with a broken table would still fail.
* **Boundary.** Any conformance fixture that describes its inputs as property
  values rather than as code points. The check has to be against an independent
  copy of the same property data, or it proves nothing.

### L6 — Count what a full-file replay covered

* **Condition.** A conformance test that iterates a fixture to its end.
* **Symptom.** Not observed. The failure mode is a green run that stopped early
  — on an iterator that yielded nothing, or on a truncated `@embedFile` — and
  reported success.
* **Fix.** Each conformance test counts the rows it replayed and compares the
  count with a constant that is a property of the fixture: 91 707 rows in
  `BidiCharacterTest.txt`, 490 846 rows and 770 241 direction-selected cases in
  `BidiTest.txt`. A pass therefore means the whole file, not an error-free
  prefix. The constants move when the Unicode revision moves, which is a
  deliberate edit, not an accident.
* **Boundary.** Any whole-file replay. The count belongs next to the parser, as a
  named constant, not inside an assertion that would have to be re-read to
  update.

### L7 — A silent upstream ignore is worth a wrapper's whole existence

* **Condition.** `SBMirrorLocatorLoadLine` rejecting a buffer that is not
  pointer-identical to the line's own (`Source/API/SBMirrorLocator.c:56`).
* **Symptom.** Not observed as a failure; observed as a code reading. A rejected
  load is ignored in silence, so a caller that passes "the same text" from a
  different buffer gets a locator that reports no mirrors, which is a perfectly
  plausible answer for a line that happens to contain none.
* **Fix.** The facade takes the buffer from the line it was given and does not
  expose a second argument for it.
* **Boundary.** This one function, at SheenBidi 3.0.0. The general rule is
  narrower than it looks: wrap an argument *when the upstream contract is
  pointer identity*, not whenever a function takes two related arguments.

### L8 — A test's oracle can be the thing that is wrong

* **Condition.** The same object checked twice in one test, with the two
  expectations written independently — here a first-strong LTR string, whose
  resolved paragraph level is `0`, checked as `0` through the original handle at
  `tests.zig:921` and as `1` through the retained handle at `tests.zig:944`.
* **Symptom.** `expected 1, found 0` at `tests.zig:944`, in Debug and in
  ReleaseSafe, one failing test out of nineteen in each
  (`…-sheenbidi-corrected-debug-37.log`, `…-sheenbidi-corrected-releasesafe-44.log`).
* **Fix.** Correct the expectation to `0`. The retention transition is not what
  is under test there — the same test already reads `0` back through the
  retained handle for the trailing full stop at `tests.zig:936`, and that
  assertion is accepted. The driver has made that edit: `tests.zig:944` now
  reads `try std.testing.expectEqual(@as(sheenbidi.Level, 0), retained.baseLevel())`.
* **Boundary.** Zig's test runner, and any suite where a value is read through
  two different handles. The discipline that generalises: before changing a
  library to satisfy a test, check whether the same test already asserts the
  other value about the same object — and record the failing assertion's
  location and both values, because "18 pass, 1 fail" alone does not say which
  of the two is wrong.
* **Status.** Observed, and the lesson is the one the green run confirms. The
  step ran twice after the edit — `…-sheenbidi-final-debug-96.log` and
  `…-sheenbidi-final-releasesafe-103.log` — both green at
  `Build Summary: 11/11 steps succeeded; 38/38 tests passed`. Each of those is
  the whole step, both modes included (§2). The two receipts above stay red
  because they describe the file as it stood when they were taken. The oracle
  was the only thing wrong, and correcting it was sufficient.

### L9 — A `.paths` entry naming a missing file is a hard configure error

* **Condition.** Writing provenance documents into a package whose manifest
  lists what a dependent receives.
* **Symptom.** Not observed. It is a manifest rule, and the manifest states it:
  a `.paths` entry naming a file that is not there is not a warning a dependent
  can shrug off, and the entry belongs "with the document it names".
* **Fix.** The documents and the manifest entries land in the same change. That
  has happened: `build.zig.zon` `.paths` lists all six documents, and all six
  files are present.
* **Boundary.** Every Zig package in this workspace, and any future provenance
  document added to one of them.
* **The other direction of the same mistake, and its repair.** When this was
  written, the manifest comment above `.paths` still said the fork's documents
  "are not listed here … they do not exist in this tree yet" — true when
  written, false as soon as the entries were added. It has since been
  corrected: the comment reads "Provenance, licence and source-integrity records
  ship with the package", and `.paths` lists all six documents. The rule is the
  one that held either way: a comment that describes the tree has to be updated
  in the same change as the thing it describes.

### L10 — A test-matrix harness is only half a gate; the profile is the other half

* **Condition.** A Zig package whose `test` step already attaches a real run
  artifact per optimize mode (`b.addRunArtifact(b.addTest(...))`), being brought
  under a `cross-test` matrix that runs `zig build test -Dtarget=TARGET` per
  target and discovers `./cross-test.profile.sh`.
* **Symptom.** Half observed. The failure mode this lesson was written for — a
  matrix run that reports nothing about the package, because the harness's own
  300 s / 900 s defaults and its own `CROSS_BUILD_JOBS` are the only settings in
  play — did not happen: the profile was sourced and every deadline in the run
  was the profile's or the command line's, by the harness's own rules. What *was*
  observed is the second mode, one step short of it: a run whose command line
  overrode the profile (`--build-jobs 4 --build-timeout 1800`, against the
  profile's 2 and 3600) ended with `x86_64-linux` and `aarch64-freebsd` at
  `per_build_timeout`, build `exit 124`, `run: not_run` — 19 pass, 32
  build_only, 2 fail, harness exit 1. The sweep that left the profile's values in
  place had no timeout at all: 20 pass, 33 build_only, 0 fail, exit 0. Those two
  runs also differ in cache directory, so the package's deadline is a plausible
  and **unisolated** explanation; a third run holding the cache constant would
  be needed to call it. The quieter failure this lesson actually warns about is
  still only a shape: a profile that shrinks the gate — defining
  `cross_build_command` or `cross_artifact` moves the harness into artifact mode,
  and setting `CROSS_MATRIX` or `TARGETS` reduces the published matrix to a
  subset — both look like a smaller, faster, green run, and this package does
  neither.
* **Fix.** Ship a settings-only profile: variable definitions, no hooks, no
  matrix, no `TARGETS`, no host path. Every value is a default the command line
  overrides. Leave anything host-specific (`CROSS_LIBC_RUNTIMES`) to the
  environment. List the profile in `.paths` so a fetched package carries it, and
  record it in `NOTICE.md` as a fork-authored file with no licence asserted.
* **Targets bound.** Any package in this workspace run under `cross-test`, on
  any matrix, with any harness default. The rule is about the *shape* of the
  profile, not about these deadlines; a package with ten fast tests does not
  need a large `CROSS_TIMEOUT`, and a package that replays a 7.6 MB fixture
  does. A `build_only` cell is compile evidence and must be recorded as such,
  never as a pass.

### L11 — A doc comment that contradicts the note above it will be believed, and a caller will reject a correct call

* **Condition.** A wrapper whose sibling functions share one block note
  describing an edge case, and whose own per-function comment restates that edge
  case slightly differently.
* **Symptom.** Two statements about one parameter, both plausible, neither
  flagged: the shared note said index `0` or past the length is
  `codepoint_invalid` with the index unchanged, while the two previous-decoders'
  own comments said `index` must be greater than `0`. Nothing failed — the tests
  passed index `0` and asserted `codepoint_invalid`, exactly as upstream
  behaves — so the contradiction survived every gate in the repository. The cost
  is on the reader: someone trusting the per-function comment rejects a call that
  is in fact correct, or adds a guard the type does not need.
* **Fix.** Delete the restatement. The per-function comment points at the shared
  note and adds only what is specific to it. Do not "fix" behaviour toward the
  comment — upstream is the tiebreak, and here `Source/API/SBCodepoint.c:283`
  and `:345` guard on `(*index - 1) < length`, which at index `0` wraps unsigned,
  fails the guard, and returns `SBCodepointInvalid` with `*index` untouched;
  `Headers/SheenBidi/SBCodepoint.h:145` and `:177` have said so all along. Two
  comment lines changed, no code line. Add no new test when the existing tests
  already assert the case — they did here, in `smoke.zig:244-247` and
  `tests.zig:1206-1211`, which is precisely why the prose was the only thing
  wrong and nothing went red.
* **Targets bound.** Any wrapper in this workspace whose functions share a
  block note and also carry per-function comments. The generalisable check is
  cheap and worth running whenever a comment is added above a declaration that
  already has one nearby: read the two together and ask whether a single call
  could satisfy both. Contradictions of this kind are invisible to a compiler
  and to a green suite, so they are found by reading, not by testing — and the
  failing case is never a red gate, it is a caller who does the wrong thing.

---

## Gate status

Every gate this file referred to when it was written has been run, and so has
the one added afterwards: §9's 53-platform `cross-test` matrix ran on 2026-10-02
at 20 pass, 33 build_only, 0 fail, exit 0. The authoritative matrix for
everything that has run — the commands, what each printed, and the receipt for
each — is in [`README.zig.md`](README.zig.md#verification-status), and it is not
repeated here. Four things a reader of *this* file needs to carry over from it:

* **`38/38` is two runs of nineteen, one per mode**, and it is the same two runs
  however many times it is printed. The two green receipts exist because the
  `test` step was invoked twice, not because one receipt is Debug and the other
  ReleaseSafe; the 2026-10-02 native round prints the same `38/38` inside one
  `zig build test smoke install` graph, and its ReleaseSafe row runs `smoke`
  only and prints no test count at all. None of these is a single-mode count, and
  none of them is nineteen more than another. §2.
* **The six cross checks are compile-and-link evidence and nothing else.** All
  six are green at `Build Summary: 6/6 steps succeeded`, twice over — the
  original receipts and a fresh 2026-10-02 baseline re-run — and neither round
  ran a binary. A green foreign target from `zig build check` is not a claim
  about the replays on that target.
* **The replays have now run on foreign architectures, but only under the full
  matrix.** Twenty cells of the 53-target sweep executed all nineteen tests in
  both modes; nineteen of those are foreign triples under the harness's own
  runner detection. That evidence belongs to the matrix gate and its receipts,
  and folding it into a `check` row would be reading one gate as another. No
  FreeBSD, OpenBSD, NetBSD, Darwin, Windows or WASI cell has run anything: those
  33 are `build_only` and stay that way.
* **The installed C surface gate is not the system mode.** It compiles, links
  and runs a C program against the archive and headers this build had just
  installed to a prefix; no system SheenBidi was present, `pkg-config` was
  never consulted, and no `-fsys=` switch was passed. §4's `-fsys=sheenbidi`
  remains ungated, at compile time and at run time.

The earlier, failing runs are kept in the matrix's own "Earlier runs" section
rather than duplicated here; those receipts are cited by name in L1–L3 and L8
above.

Still unobserved, named where each one occurs:

| Item | Where |
|---|---|
| replaying `git archive` against `9bdf0c279f…cac4a28` — needs a re-fetch of upstream, which this workspace does not have | [`UPSTREAM.md`](UPSTREAM.md) |
| `zig build -fsys=sheenbidi` — needs an installed `libSheenBidi` at this manifest's pinned 3.0.0 with its own matching header | §4, and [`README.zig.md`](README.zig.md#not-observed) |
| the package round **after** the profile joined `.paths` — filtered `zig fetch`, the 218-record `sha256sum -c` inside it, and its `consumer/` | §9, and [`README.zig.md`](README.zig.md#not-observed) |

## Left for the driver

Nothing is outstanding that this workspace can close. The two items that stood
on this list when it was written — the six cross checks and
`sha256sum -c UPSTREAM.sha256` — have both since been run and are green in the
matrix, and §9's 53-platform matrix has since been run too. Three remain: the
first two each need something this workspace does not have, and the third is a
re-run of a gate that already has receipts, scheduled after these documents
freeze so that the copy it produces contains the final text.

1. **Replay the archive digest.** With a re-fetch of upstream:

   ```
   git -C <clone> archive --format=tar cfe430e7375a7845b679adae9d51dac6deaa8858 | sha256sum
   ```

   The output must read
   `9bdf0c279f5070f9d397d8f1446acd0bf8eebb802da80ca4cb6b57fb1cac4a28  -`,
   the receipt recorded in [`UPSTREAM.md`](UPSTREAM.md). This is the one link
   in the provenance chain no local run can close: the 218-record check binds
   this tree to the record, and only a re-fetch binds the record to upstream.
2. **Gate `-fsys=sheenbidi`.** It needs an installed `libSheenBidi` at this
   manifest's pinned 3.0.0 together with the header that release installed.
   Nothing else is waiting on it, and nothing about the bundled path depends on
   the outcome.
3. **Re-run the materialised-package round after the profile landed.** The
   filtered `zig fetch` at receipt 440, the 218-record `sha256sum -c` inside that
   copy at 443 and its `consumer/` at 444 all predate `cross-test.profile.sh`.
   Re-run the three against the frozen tree and the new copy becomes the first
   evidence that `.paths` delivers the profile; until then that line of the
   manifest is `SOURCE-CONFIRMED` only, and the identity of that new package
   must be read from its own fetch receipt rather than carried over from
   `sheenbidi-3.0.0-PIPqq_cnPAHHpPnjFuv7nc5-dgtiNxsmOpfmw-Q-ZnsO`.

## The 2026-10-04 contract migration

Everything below was decided for this migration. The gate matrix above is
evidence about the package as it stood on 2026-10-03; this section is the set of
changes that evidence no longer covers. Entries are numbered `M1`–`M8` so they
cannot be confused with the decisions and lessons above, which stay where they
are.

**Partly gated since.** Sixteen gates ran on 2026-10-04 between 15:09 and 15:20
UTC — `zig build test smoke install` across both linkages and all four optimize
modes, eight of them with `-Druntime=true` — all exit 0, receipted under
`…/contract-physics-lua/current-native-evidence/`. They cover M4's delivery half
and the runtime load path; they observed `lib/pkgconfig/SheenBidi.pc` and only
that file in `lib/pkgconfig`, which is M4's corrected ownership claim. They do
**not** cover the derivations, `bin/misuse`, `zig fetch`, the six-target check,
the 53-platform matrix, or the run-step `has_side_effects` change, which landed
after them. Each decision below keeps its own status line, and none of them was
moved by a document edit.

### M1. Upstream's README is preserved under its own name

**Condition.** The fork needed a `README.md` of its own — deviations, matrix,
consumption — in a canonical order, and upstream's README carried the licence
grant, the copyright line and the object-model description that this
documentation cites by line number.

**Decision.** Upstream's README is preserved byte for byte as
`README.upstream.md`, and `README.md` is the fork's. `UPSTREAM.sha256`'s record
line changed name and not digest, the count stays 218, and every line citation
moved with the bytes — `README.upstream.md:169-184` is the grant, `:171` the
copyright, `:45-69` the object model, `:71-72` the dependency statement.

**Why the digest is trustworthy.** The driver's extraction receipt
`local://foundation-contract-upstream-readme-proof.json` records
`34376a69…ae1c8` for `README.upstream.md`, which is the digest the record
carried for `README.md`. That is what makes this a rename and not a re-hash.

**Cost.** Every citation in the package that named upstream's README by line
had to move, and a `git diff` against the pinned commit must now name
`README.upstream.md`: comparing the fork's own `README.md` with upstream's
commit is a different question and would report a false difference.

**Status.** `PENDING-VERIFICATION`. The record was updated; `sha256sum -c` has
not been re-run since.

### M2. The fork's own files got a licence, by owner authorization

**Condition.** Entries 14, 17 and 18 had withdrawn an Apache-2.0 offer nobody
had made and recorded the fork's files as unassigned, because upstream's grant
does not reach additions this fork made.

**Decision.** The owner authorized a per-project licence for the fork's
additions. This project's is `Apache-2.0`, matching upstream's primary term, with
no copyright line invented and nothing attributed to upstream authors. The
authorization and the grant are in `FORK-LICENSE.md`; `NOTICE.md` carries the
three-way split.

**Why Apache-2.0 and not something newer or older.** The tree is overwhelmingly
upstream's, upstream's term is Apache-2.0, and one licence for one distribution
is worth more than variety. It also brings the obligations this fork already
discharges: a `NOTICE` file, a statement of changes, and the patent-grant
termination clause.

**What it does not do.** It does not reach upstream's work, and it does not reach
the eleven Unicode data files, which stay under the terms their own headers name.

**Cost.** Files authored before the grant carry no header until they are next
rewritten; the SPDX line is one comment line per file and the grant lives in one
document rather than in six headers.

**Status.** `SOURCE-CONFIRMED` as a licence fact. Nothing was gated.

### M3. The install closure carries the licence material, not only the artifact

**Condition.** A prefix install and a Nix output could previously ship a binary
with its licence three directories away, and the Unicode terms reached only
whoever had the source tree.

**Decision.** `zig build install` and the Nix derivation install the same
document set under `share/doc/sheenbidi/`: `LICENSE`, `NOTICE.md`,
`FORK-LICENSE.md`, both READMEs, `README.zig.md`, `UPSTREAM.md`,
`UPSTREAM.sha256`, `CHANGELOG.md`, `FORK-NOTES.md`, and the eleven Unicode data
files unmodified under `share/doc/sheenbidi/unicode/`.

**Why the Unicode files ship in the output at all.** They are separately
licensed material whose terms are named inside the files, and a recipient of the
built package must receive those terms with the data. Upstream does not install
them; that is upstream's build, and this fork's obligation is not upstream's.

**Why one rule for both paths.** A prefix install and a Nix closure are audited
the same way, and a second, divergent install path would eventually produce two
different claims about what a recipient has.

**Status.** `PENDING-VERIFICATION`. Nothing has inspected an install since.

### M4. One source-only Nix derivation, two variants, no sibling import

**Condition.** The package had no Nix packaging at all, and a sibling-workspace
import or a host path would make a "portable" package that only builds on this
machine.

**Decision.** `package.nix` is one uncurried derivation returning **one** result,
with `linkage` as its only variant parameter; the variants exist at the two entry
points, not inside it. `flake.nix` exposes `static`, `shared` and `default`, and
`devenv.nix` exposes the same two as lazy `outputs`. `default` is `static`
because that is this SDK's existing policy. The derivation imports nothing from
a sibling workspace, names no host account, store path or absolute mount,
downloads nothing, adds no C flag, filters version control and build state out of
the source it hands the build, and is install-only: one `zig build` with one
optimize selection, `-Dcpu=baseline`, `-Dlinkage=<variant>` and `--prefix "$out"`,
with both Zig caches inside the sandbox `TMPDIR`.

**Why `build.zig` stays the only writer.** It installs the library, the headers,
the licence and provenance documents, the Unicode data and the pkg-config
metadata. An earlier version of this derivation re-installed that same set in
`postInstall`; that was removed, because two writers for one path means two
places to be wrong. The derivation then still added one file of its own,
`lib/pkgconfig/sheenbidi.pc`, and that is gone too.

**Why that last file was deleted rather than reconciled.**

* **Condition.** A Nix derivation whose `build.zig` already generates a `.pc` from
  an upstream template, where the derivation also adds a `.pc` of its own.
* **Symptom.** One library described by two files, disagreeing silently. Here
  `build.zig`'s `addPkgConfig` had been writing and installing
  `lib/pkgconfig/SheenBidi.pc` all along (`build.zig:944`, `:977`) while the
  derivation's `sed` wrote `lib/pkgconfig/sheenbidi.pc` beside it — base names
  differing only in case, both carrying `Name: SheenBidi` and
  `Libs: -lSheenBidi`. `pkg-config` answered according to the spelling it was
  asked for, and the two disagreed on the only field that depends on the variant:
  the graph appends ` -DSB_CONFIG_DLL_IMPORT` to `Cflags:` for a dynamic build
  (`build.zig:972`), where the derivation substituted
  `@SHEENBIDI_PKGCONFIG_CFLAGS@` with nothing, so `nix build .#shared` described
  a shared library without the decoration its headers require on `_WIN32`.
  Nothing failed. Every document that described the delivery repeated the
  opposite claim — that the graph generates no `.pc` and the derivation adds the
  only one — which is what kept it invisible: the docs agreed with each other and
  disagreed with the build graph.
* **Fix.** Delete the derivation's writer; keep the graph's. It needed no prefix
  fixing because the graph writes `prefix` as `${pcfiledir}/../..`, relative to
  the file pkg-config found, so a fixed `$out` is a prefix like any other to it.
  Keep the installed base name equal to `library_name`, so `-lSheenBidi` and the
  file describing it spell the package identically.
* **Targets bound.** Any Nix-packaged SDK in this workspace whose `build.zig`
  already writes a `.pc` from an upstream template. The rule is narrower than
  "delete `postInstall`": a derivation may legitimately add a file the graph
  cannot produce, but it must not add one the graph already writes under a
  different spelling, and where two writers share a path the variant-dependent
  fields (`Cflags:` above all) must agree — otherwise the conflict is a silent
  wrong answer rather than a build failure. A same-field `.pc` disagreement is
  invisible to every other check in the repository, because an archive with
  unusable metadata still compiles, installs and links.

**Why `dontInstall` is not set.** It would disable the Zig setup hook's real
install phase. `dontBuild` and `dontConfigure` are set instead, so exactly one
phase runs.

**Why pkg-config metadata is generated from upstream's template, and by whom.**
Upstream already ships `sheenbidi.pc.in`, so the file's field set and library
spelling are upstream's rather than a second description this fork invented —
but `build.zig` is what writes it, not the derivation. Upstream substitutes
CMake's configure-time absolute `@CMAKE_INSTALL_PREFIX@`; this graph never fixes
a prefix, and writes `prefix` as `${pcfiledir}/../..` relative to the file
pkg-config found, so the installed metadata is correct wherever `--prefix` put
it and a Nix `$out` needs no substitution of its own. That is what removed the
derivation's reason to exist alongside the graph's.

**Why no `devShells` in the flake.** The development environment is devenv, and
a flake dev shell would be a second, unexercised one.

**Status.** Partly observed. A **prefix install** was observed on 2026-10-04:
the sixteen `zig build test smoke install` gates name `install generated to
pkgconfig/SheenBidi.pc` in their step summaries, and the `sheenbidi-static` and
`sheenbidi-shared` prefixes are readable on disk with `lib/pkgconfig/SheenBidi.pc`
and nothing else beside it — the capitalised name `build.zig:944`/`:977` write,
with the per-variant `Cflags:` difference the removed derivation's file got
wrong. So the corrected ownership claim above is observed on the `zig build
install` route. The **Nix** route remains `PENDING-VERIFICATION`: neither
derivation has been built or inspected, so what an `$out` carries is still a
source-confirmed prediction, not a result.

### M5. devenv is canonical; where its state goes is the caller's

**Condition.** This repository sits on an NFS volume. A devenv shell that keeps
its state in `.devenv/` and its Zig caches beside it puts build state on a
network filesystem, which the workspace's storage policy forbids — and entering
a shell must not compile the SDK.

**Decision.** `devenv.nix` holds tools only (Zig 0.16.0, pkg-config), exposes this
package's own build as namespaced `sheenbidi:*` tasks, and exposes the same
`package.nix` the flake uses as lazy `outputs.static` and `outputs.shared`.
`devenv build outputs.static` is therefore a real build from inside the shell,
not an echoing task.

**Where the state goes is the caller's, not the file's.** `devenv` puts runtime
sockets under `/tmp` and keeps state under its own home unless `TMPDIR`,
`DEVENV_HOME`, `XDG_RUNTIME_DIR` and the Zig caches are supplied, so the driver
supplies them on approved scratch and verifies where state actually landed. An
earlier version of this file redirected those variables from `HOST_SCRATCH_ROOT`
and refused to evaluate without it; both were removed. A committed file cannot
move state that was created before the shell was entered, and requiring this
site's helper variable would make the package unusable for a caller who brings
its own scratch. What `devenv.nix` can honestly promise is only that it adds no
path of its own and erases none of the caller's.

**Cost.** `.gitignore` grew entries for `/.devenv/`, `/.devenv.flake.nix`,
`/devenv.local.nix` and `/.direnv/`, so `direnv allow` cannot dirty this NFS
working copy; `.envrc` and the two lock files are deliberately not ignored.

**Current state of the two lock files.** A `flake.lock` is present in this
working copy, pins `nixpkgs` to the same commit `flake.nix` names, and **ships in
`build.zig.zon` `.paths`** (`build.zig.zon:102`), on the same ground as `.envrc`:
a copy carrying the flake without its lock would declare a pin and ship none. No
`devenv.lock` exists in this tree and none is listed — no file is invented to fill
the slot. The ownership rule this file records still holds: no file of this
package writes either one; the workspace driver does.

**Why the derivation still filters both out.** Two different axes, and the
distinction matters when reading a derivation's source filter. `flake.lock` is
package content — it ships — and is dropped from `src` only because `zig build`
never reads it. That makes it the build's input rather than the package's
contents, and by the time the derivation runs the Nix flake frontend has already
resolved the locked inputs. Excluding a lock there is not a defect, and this
entry previously recorded it as one by calling it machine state; that was wrong
once the lock became package content, and the reasoning above replaces it.

**Status.** `PENDING-VERIFICATION`. No shell has been entered under a gate.

### M6. Static means a static library, and the documents say so

**Condition.** "Static" in a package description invites the reading "a wholly
static executable". SheenBidi allocates through `malloc`/`free` and copies
through `memcpy`/`memmove`, so that reading is false in every configuration.

**Decision.** Every document that mentions the static variant says what it is —
a static library artifact — and says why the stronger reading cannot hold. The
Nix derivation asserts its `linkage` value and its Zig version rather than
accepting any string.

**Cost.** None worth naming; this is a sentence that has to be written once and
kept true.

### M7. The DLL macros are keyed to the artifact kind, not to the target

**Condition.** `SB_PUBLIC` is `__declspec(dllexport)`/`__declspec(dllimport)`
only under `_WIN32` and only when `SB_CONFIG_DLL_EXPORT`/`SB_CONFIG_DLL_IMPORT`
is defined (`Headers/SheenBidi/SBBase.h:30-42`); upstream's CMake defines them
for a DLL build (`CMakeLists.txt:123-127`). A shared build that omitted them on
Windows would link as an empty shell.

**Decision.** `-Dlinkage=dynamic` defines `SB_CONFIG_DLL_EXPORT` on the C compile
line and `SB_CONFIG_DLL_IMPORT` on the translation line, in bundled and
`-fsys=sheenbidi` mode alike, with no target test because the macros are inert
off `_WIN32`. In system mode the macro follows `system_linkage`, and
`preferred_link_mode` follows the same value, so the header decoration and the
linker cannot describe two different libraries. Under the default `static`
neither is defined and a consumer needs no define.

**Status.** `SOURCE-CONFIRMED` for the rule; `PENDING-VERIFICATION` for the
build, including the Windows shared artifact itself, which has not been built.

### M8. A canonical task names its own directory; the working directory is not it

**Condition.** A devenv task entered with `--from path:<this SDK>`, so devenv
generates the wrapper with the *project* directory as its working directory.
`DEVENV_ROOT` names that project, and `devenv tasks run` does not run
`enterShell` — the same run shows `devenv:enterShell` executing for
devenv shell` and absent from `devenv tasks run`. Two inherited locations are in
play here and neither inherited one is this checkout: the working directory and
`DEVENV_ROOT` are the same project directory in that run, and this SDK is a
third path entirely.

**Symptom.** Two 2026-10-04 acceptance gates failed on the directory rather than
on the build: `line 3: cd: consumer: No such file or directory` and
`sha256sum: UPSTREAM.sha256: No such file or directory` (receipts
`…-sheenbidi-devenv-consumer.log`, `…-sheenbidi-devenv-integrity.log`). The file
parsed, `devenv info` listed all seven names, and the failure came out of the
generated `/nix/store/…-sheenbidi-consumer` wrapper itself.

**Fix.** One binding — `./.`, rendered by `builtins.toString` and quoted by
`pkgs.lib.escapeShellArg` — becomes the first line of every exec, with a
second binding for `consumer/`. `integrity` and `consumer` are the two that
fail loudly without it; `build`, `test`, `smoke`, `check` and `install` would
fail the same way from the same cause and were not run that day. A per-task
`cwd` option would not have covered the whole surface: the same run recorded
the same `/nix/store/…-<name>: line N:` wrapper prefix on other SDKs'
script-form entries, so the body has to move, not the option.

**Boundary.** devenv 2.4.1, `--from path:<SDK>`, `devenv tasks run`, any SDK
whose task or script bodies use relative paths. Unbound to this package: no
build graph, test, fixture or facade line changed, and the Unicode data and the
Bidi API are untouched — the whole edit is inside `devenv.nix` and the documents
that describe it.

**A prefix is a delivery output, so it follows the cache.** `sheenbidi:build`
runs the default step, and that step *is* the install step — `build.zig:979`
attaches `SheenBidi.pc` to `b.getInstallStep()`, and the library, the headers
and the licence records are attached there too — so it wrote `zig-out/` into
this checkout, and `sheenbidi:install` wrote under `$TMPDIR` with a `/tmp`
fallback this workspace's storage policy does not accept. Both now take an
explicit `--prefix` beneath the exported `ZIG_LOCAL_CACHE_DIR`, else
`$XDG_CACHE_HOME`, else `$TMPDIR`, and with none of the three they name the
variable to set and exit non-zero.

`test`, `smoke`, `check` and `consumer` were left without a `--prefix` on
purpose: their steps depend on test, run and compile steps only
(`build.zig:1232`, `:1203`, `consumer/build.zig:79`) and never on the install
step, so they produce no delivery output and a prefix on them would be
decoration. A caller's own `--prefix`, arriving in `"$@"`, still overrides both
defaults, exactly as it did before.

### What this migration moved under the documentation

Line citations into files another role rewrote were repointed in the documents
that describe current state — `build.zig:211` → `build.zig:441`,
`build.zig:329-340` → `build.zig:631-648`, `build.zig:291-296` →
`build.zig:563-568`, `.github/workflows/verify.yml:57-58` → `:83-84`. The
**earlier** entries that cite those numbers are left alone on purpose: they
describe the file as it stood when they were written, and `CHANGELOG.md` entries
20 and later record the move rather than rewriting history silently.

### Gates this migration added, none of them run

The list is in [`README.zig.md`](README.zig.md#verification-status) under
"Pending verification for this migration", because that table is the driver's.
Nothing in this section is a result, and no receipt exists for any of it.

### One thing this migration did not close

`zig/root.zig` — the facade, owned by the API role — describes the product of a
`zig build` as `libSheenBidi.a`. With `-Dlinkage=dynamic` the artifact is
`libSheenBidi.so.3.0.0` plus its two symlinks, so that comment is now
incomplete. This file's owner does not edit the facade, so the correction is
recorded here and raised with the driver rather than made from the wrong seat.
