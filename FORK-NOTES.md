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
`SheenBidi.cmake.in`, `sheenbidi.pc.in`, `LICENSE` and `README.md`. **218
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
