# CHANGELOG — fork-only divergences

Upstream's release history lives in its own repository. This file records **only**
what this fork changed relative to SheenBidi `v3.0.0`
(`cfe430e7375a7845b679adae9d51dac6deaa8858`), and it is written so a re-sync can
replay it. Numbers are stable identifiers; never renumber them.

Statuses below are the workspace's: **observed** means the driver ran a gate and
the output is in the named receipt; **pending** means the change has landed and
no gate has looked at it yet.

## 1. Added the Zig 0.16 package

`build.zig`, `build.zig.zon`, `zig/translate.h`, `zig/root.zig`,
`zig/conformance/`, `tests.zig`, `smoke.zig`, `consumer/` and
`.github/workflows/verify.yml` are new. New module: `sheenbidi`. New artifacts:
`zig-out/lib/libSheenBidi.a` and `zig-out/include/SheenBidi/*.h`. The build
compiles upstream's C from this repository, nothing is downloaded, no upstream
build system runs, and `build.zig.zon` declares no dependencies. No upstream
source file is touched.

## 2. Built upstream's unity unit, at C90, with the text API off

**Condition.** SheenBidi can be built as one unity translation unit or as
separate ones, and its experimental text API can be compiled in or out.

**Decision.** `Source/SheenBidi.c` with `-std=c90 -DSB_CONFIG_UNITY` and without
`SB_CONFIG_EXPERIMENTAL_TEXT_API` and without
`SB_CONFIG_ALLOW_NON_ATOMIC_FALLBACK`. That file `#include`s all 32 checked-in
`.c` units, so the archive is the whole library and not a hand-picked subset.
The switch is unity because that is upstream's own default — `CMakeLists.txt`
has `option(SB_CONFIG_UNITY ... ON)` and `meson_options.txt` says
`unity_mode = enabled` — and the build list is deliberately one entry long: a
glob or a per-file list would let a unit be added to or dropped from the archive
without a decision.

The text API is off because `Headers/SheenBidi/SBConfig.h:39` ships
`SB_CONFIG_EXPERIMENTAL_TEXT_API` commented out. With it off,
`SB_TEXT_API_SUPPORTED` is 0 and the three text units contribute no definitions,
so the experimental API is absent from the archive rather than stubbed. Omitting
`SB_CONFIG_ALLOW_NON_ATOMIC_FALLBACK` is a correctness choice, not a preference:
forcing the non-atomic path on a threaded target would make a data race compile
cleanly.

`-std=c90` is pinned rather than left to the compiler's default because
`Source/API/SBBase.h` and `Source/Core/ThreadLocalStorage.h` select their atomics
and TLS backend from `__STDC_VERSION__`: at C11 and above they take the
`USE_C11_*` branches and include `<stdatomic.h>`, below it they use the
compiler-builtin `__atomic_*` and `__thread` paths that need no platform header.
All three of upstream's build systems ask for C90, so pinning it keeps that
decision identical on all six cross targets this package claims.

**Status: observed** — the C core built and was linked into the test, smoke and
consumer binaries in every native gate. Receipts that compile it rather than
reuse it: `…-sheenbidi-corrected-consumer-45.log` reports
`compile lib SheenBidi Debug native success 2s MaxRSS:122M`,
`…-sheenbidi-initial-debug-13.log` reports the same step at `success 35s`, and
`…-sheenbidi-installed-artifact-gruenau8-175.log` reports it again at
`success 4s MaxRSS:115M` on a second host, installing to an explicit prefix.
The other receipts report `compile lib SheenBidi Debug native cached`, which
means those runs reused an archive an earlier invocation produced — not that
the C was never built here. Every step in the native gate set
(`…-final-install-106.log`, `…-final-smoke-91.log`, `…-final-debug-96.log`,
`…-final-releasesafe-103.log`, `…-final-consumer-107.log`) is `cached` or
`reused`, so those five establish linking; the compile evidence is the three
receipts named above.

## 3. Put the system-library mode behind `-fsys=sheenbidi`, not a `-D` option

**Condition.** `b.systemIntegrationOption` writes to the build graph's
system-library map, which the build runner fills from `-fsys=` and `-fno-sys=`.
The `-D` option map is a different map, so `-Dsystem=sheenbidi` would parse and
do nothing.

**Decision.** `-fsys=sheenbidi`, default off. In that mode no archive of ours is
produced, nothing is installed, and both the translation and the facade bind to
the installed library: the bundled include path is not added, so
`<SheenBidi/SheenBidi.h>` is the header the installed library was installed
with, and pkg-config supplies the name and flags (`-lSheenBidi`, capitalised as
upstream installs it). `check` in that mode stays on the requested target and
says so instead of reporting a six-target matrix it never looked at.

**Status: not run.** The mode has never been gated in this workspace; no
installed `libSheenBidi` was available and none is claimed.

## 4. Appended Zig entries to `.gitignore`

Upstream's 27 lines — everything from `## Build directories for CMake` through
the blank line that ends the file, above the appended section — are kept
verbatim; a `## Zig build output` section with two entries, `/.zig-cache/` and
`/zig-out/`, is appended. This is the only upstream file this fork edits, and it
is therefore deliberately absent from `UPSTREAM.sha256`; the change is recorded
in `NOTICE.md` instead.

## 5. Made the translation root an aggregate include, and let the include path decide

`zig/translate.h` is one line: `#include <SheenBidi/SheenBidi.h>`. It is
deliberately spelled with angle brackets and deliberately not
`Headers/SheenBidi/SheenBidi.h`, because the include path is what decides which
header answers: `build.zig` adds `-I Headers` in bundled mode, and adds none in
system mode. The declarations that reach the facade and the archive that gets
linked therefore come from one place in both modes, which is the whole reason
this file exists rather than translating the header path directly. No macro is
defined there and no declaration is added.

`SB_CONFIG_UNITY` is deliberately absent from that header: it only changes
`SB_INTERNAL` to `static` for the library build, and setting it on a translation
of declarations would say something false about a consumer's view of the
headers.

## 6. Added the conformance harness and pinned the fixtures as whole files

`zig/conformance/level.zig`, `character_test.zig`, `bidi_test.zig` and
`bidi_class.zig` parse the two UAX #9 conformance fixtures and are used only by
`tests.zig`. `BidiTest.txt` states its cases as `Bidi_Class` property values
rather than code points and permits an implementation to "randomly pick
characters from those with the same Bidi_Class values"; the harness uses one
fixed representative per value and checks **every** representative against
Unicode's own `DerivedBidiClass.txt`, so a wrong representative fails loudly
instead of quietly replaying a different property sequence.

Each conformance test counts the rows it replayed and compares the count with a
constant — 91 707 data rows in `BidiCharacterTest.txt`, 490 846 rows and 770 241
direction-selected cases in `BidiTest.txt` — so a green run means the whole file
was replayed and not an error-free prefix. Those three constants are properties
of the fixtures, not of the library, and a UCD bump moves them.

**Status: observed** — both conformance tests completed in Debug and in
ReleaseSafe in both red test receipts (`…-corrected-debug-37.log`,
`…-corrected-releasesafe-44.log`), where the only failure either reports is
entry 11's, and in both current test receipts (`…-final-debug-96.log`,
`…-final-releasesafe-103.log`), which are green at `38/38 tests passed`. So the
row-count comparison this entry describes has now been observed *passing* in
both modes, not only observed not to fire.

## 7. Repaired a method call on a bare struct literal

**Condition.** Zig 0.16 does not accept a method call directly on an unparenthesised
struct literal.

**Symptom.** `tests.zig:555:105: error: expected ',' after argument` on
`sheenbidi.BaseLevel{ .explicit = 126 }.toC()`. The test step failed to compile
in both modes, exit 1 (`local://foundation-expansion-sheenbidi-initial-debug-13.log`).

**Fix.** Parenthesise the literal: `(sheenbidi.BaseLevel{ .explicit = 126 }).toC()`.

**Status: observed** — no later receipt reports this error. The two red test
receipts get past it and fail later, at runtime, on entry 11's assertion, and
the current test receipts compile clean and are green.

## 8. Replaced a runtime `for` over `std.meta.fields` with `inline for`

**Condition.** `builtin.Type.EnumField.value` is typed `comptime_int` with a
"struct requires comptime because of this field" note, so a runtime loop over
`std.meta.fields(SomeEnum)` cannot read `field.value`.

**Symptom.** `zig/conformance/bidi_class.zig:183:29: error: values of type
'builtin.Type.EnumField' must be comptime-known, but index value is
runtime-known`, with the note at `lib/std/builtin.zig:731:16`. Four compilation
errors in the test step across both modes
(`local://foundation-expansion-sheenbidi-repaired-debug-21.log`).

**Fix.** `inline for`, so each `field` is a comptime value and the representative
table is checked for every `Bidi_Class` at compile time.

**Status: observed** — no later receipt reports this error, and the current
test receipts compile clean.

## 9. Dereferenced the agent pointers the locators return

**Condition.** `SBScriptLocatorGetAgent` and `SBMirrorLocatorGetAgent` are
declared as returning a C pointer to a struct embedded in the locator, and
translate-c publishes that as `[*c]const struct`, which has no field access.

**Symptom.** `zig/root.zig:791:34: error: type '[*c]const
translate.struct__SBScriptAgent' does not support field access` and the same for
`[*c]const translate.struct__SBMirrorAgent` at `:856:33` — two of the four
errors in `…-repaired-debug-21.log`.

**Fix.** `c.SBScriptLocatorGetAgent(self.ref).*` and
`c.SBMirrorLocatorGetAgent(self.ref).*`. Both pointers come from an agent
embedded in the locator and are never null, so the pointee is read directly; the
facade says so in a comment at each site rather than leaving the deref
unexplained.

**Status: observed** — no later receipt reports this error, and the current
test receipts compile clean.

## 10. Added the provenance and documentation set

`UPSTREAM.md`, `UPSTREAM.sha256` (218 records), `NOTICE.md`, `README.zig.md`,
`CHANGELOG.md` and `FORK-NOTES.md`. The integrity record hashes only the
upstream-owned files `.paths` ships, so `sha256sum -c UPSTREAM.sha256` works
both in a clone and in a package a dependent fetched. Its header names every
exclusion and why, and it covers the `LICENSE` text and the Unicode fixtures, not
only the sources the build compiles.

**Status: observed** — the 218 records were written and re-derived from the
written file with the same raw-byte method (218 re-derived, 0 mismatches), and
the gate itself has since been run here: `sha256sum -c UPSTREAM.sha256` exits 0
with 218 lines of output, every one of them `<path>: OK`, nothing failed
(`…-sheenbidi-immutable-source-integrity-120.log`). This entry's `pending`
status is closed. The gate is also wired: `.github/workflows/verify.yml:57-58`
runs `sha256sum -c UPSTREAM.sha256` unconditionally as the `native` job's
"Immutable source and Unicode fixture integrity" step, ahead of `zig build`.

Entry 15 goes further and runs this same record **inside** a package
materialised by `zig fetch`, which is the run that makes "in a package a
dependent fetched" an observation rather than an argument from `.paths`.

## 11. One test in the suite pinned a wrong expected value

**Condition.** The test `a paragraph outlives its algorithm and retain keeps the
object alive` runs on `"car means \u{05D0}\u{05D1}\u{05D2}."`, a string whose
first strong character is LTR.

**Symptom.** Both test gates were red with the same single failure. At
`tests.zig:944`, `retained.baseLevel()` returned `0` where the assertion expected
`1`: `expected 1, found 0`, `18 pass, 1 fail (19 total)` in Debug and again in
ReleaseSafe, `36/38 tests passed (2 failed)` overall
(`local://foundation-expansion-sheenbidi-corrected-debug-37.log`,
`…-corrected-releasesafe-44.log`). Those two receipts are the historical
record of the failure and are superseded by the green pair named under Status.

**Diagnosis.** Rules P2 and P3 resolve that string to level `0`, which is what
the same test already asserts at `tests.zig:921` on the original handle, twenty
lines earlier. The retained handle and the original are the same object, and the
next value the test pins through it — the resolved level of the trailing full
stop, `0` at `tests.zig:936` — is accepted. The expected value at line 944 is the
oracle's error, not the library's.

**Fix.** Correct that one expected value to `0`. The driver has made that edit:
`tests.zig:944` now reads
`try std.testing.expectEqual(@as(sheenbidi.Level, 0), retained.baseLevel())`.

**Status: observed, and the correction is gated.** Two gates have run since the
edit: `…-sheenbidi-final-debug-96.log` and `…-sheenbidi-final-releasesafe-103.log`,
each green at `Build Summary: 11/11 steps succeeded; 38/38 tests passed` — 19 of
19 in Debug and 19 of 19 in ReleaseSafe, in each receipt, because the `test`
step runs both modes itself. The full 91 707-row and 490 846-row / 770 241-case
UAX #9 replay therefore *passed* in both modes rather than merely completing,
and the other 15 tests pass. Nothing about this entry is outstanding; the two
red receipts quoted above stay as the historical record of the failure and
describe the file as it stood when they were taken.

## 12. Both integration items are closed

**`.paths` — done.** `build.zig.zon` `.paths` lists `UPSTREAM.md`,
`UPSTREAM.sha256`, `README.zig.md`, `NOTICE.md`, `CHANGELOG.md` and
`FORK-NOTES.md`, and all six files are present. The rule the entry quoted still
holds — a `.paths` entry naming a missing file is a hard configure error, which
is why the entries belong with the documents — and it is now satisfied. The
manifest's own comment above the list has since been corrected as well: it now
reads "Provenance, licence and source-integrity records ship with the package",
which is what it says below it. The comment used to claim the documents "are
not listed here … they do not exist in this tree yet", which was true when
written and false once the entries were added; a comment that describes the tree
has to move in the same change as the thing it describes.

**The integrity step — already wired.** `.github/workflows/verify.yml` has
three jobs, native, cross and consumer. Its `native` job's first step is
`.github/workflows/verify.yml:57-58`, named "Immutable source and Unicode
fixture integrity", whose `run:` is exactly `sha256sum -c UPSTREAM.sha256`,
ahead of `zig build`. There was never a gap to close here and no fourth job is
needed, so nothing is outstanding.

Neither item is outstanding any more. `sha256sum -c UPSTREAM.sha256` has been
run in this workspace and is green — exit 0, 218 records, every line `OK`
(`…-sheenbidi-immutable-source-integrity-120.log`) — so entry 10 is `observed`
here as well as wired in CI.

Entry 15 then closes the gap entry 12 could not: it materialises the package
with `zig fetch` and runs the record and `consumer/` inside the copy, so `.paths`
is observed complete against the record rather than only checked for the six
files it names.

## 13. Gated the installed C surface from C, not only from Zig

**Condition.** Every other gate in this package reaches SheenBidi through the
Zig facade. A facade can be correct while the C surface a C caller compiles
against — the installed headers plus the installed archive — is not, and none of
the facade gates would notice. This fork is a C library first, so the C
contract needs its own gate.

**Decision.** `.github/workflows/verify.yml`'s `native` job writes a C program
inline, compiles it with `zig cc -I zig-out/include
zig-out/lib/libSheenBidi.a`, and runs it, between `zig build` and
`zig build test`. No configuration macro is passed to that program and none is
needed: the only `SB_CONFIG_*` the core is built with is `SB_CONFIG_UNITY`,
which says nothing about a consumer's view of the headers, and
`Headers/SheenBidi/SBConfig.h` ships every macro commented out. The expected
values are derived from the rules of UAX #9 in the program's own comments rather
than read back out of this build, so a wrong answer and a wrong expectation fail
it differently.

**What it pins.** On `"abc "` followed by U+05D0 HEBREW LETTER ALEF and U+05D1
HEBREW LETTER BET — six code points in eight UTF-8 code units —
`SBCodepointSequenceGetCodepointAt` walks the Hebrew pair and leaves a rejected
index where it was; an explicit base level of `0` and the header's own
`SBLevelDefaultLTR` request both resolve to a base level of `0` with levels
`0 0 0 0 1 1 1 1`; `SBParagraphCreateLine` yields one line of two visual runs
at offsets `0` and `4`, length `4` each, at levels `0` and `1`; and the
retained line and the retained paragraph are still readable after the handles
that created them are released.

**Status: observed.** The driver installed to a prefix on a second host
(`zig build --prefix <dir>`, green, with the core compiled rather than reused —
`compile lib SheenBidi Debug native success 4s`,
`…-sheenbidi-installed-artifact-gruenau8-175.log`) and then compiled and ran
the same program against those installed artifacts and nothing else: exit 0,
58 `ok` lines and no `FAIL`, closing on
`the installed C surface compiled, linked and ran`
(`…-sheenbidi-installed-C-surface-180.log`).

**What it is not.** It is not entry 3. That mode needs an installed
`libSheenBidi` at this manifest's pinned 3.0.0 with its own matching header and
remains unrun; this gate needs nothing but the artifacts this build produced a
moment earlier, and involves no system library, no `pkg-config` lookup and no
release-mismatch question. The installed contract is documented in
[`README.zig.md`](README.zig.md#the-installed-c-contract); the full gate matrix
is in its [verification status](README.zig.md#verification-status).

## 14. Ignored consumer output and withdrew an unauthorised grant

Appended `consumer/.zig-cache/` and `consumer/zig-out/` to `.gitignore`
without replacing upstream's ignore rules. These are generated build outputs,
not source or conformance fixtures.

`NOTICE.md` and `README.zig.md` no longer offer Apache-2.0 for fork-authored
files: no owner authorised that grant. Their licence is unassigned. Upstream's
Apache-2.0 grant and the separate Unicode data terms remain unchanged.

## 15. Gated the shipped package, not only this working tree

**Condition.** Entries 10 and 12 make claims about what a *dependent* receives:
that the integrity record "works both in a clone and in a package a dependent
fetched", and that `.paths` names every file the package needs. Every gate
before this one ran against this working tree, where the whole repository is
present whatever `.paths` says, so both were arguments from the manifest rather
than observations. A path dependency is used in place, so nothing in the build
reads `.paths`: the only thing that exercises it is a real materialisation.

**Status: observed.** The driver ran `zig fetch` over this package directory
from an external approved scratch build root
(`/home/tmp2/gertullj/scratch/foundation-libs/session-01a0f400/package-fetch`),
not from inside the repository: exit 0, and the package identity it printed is
`sheenbidi-3.0.0-PIPqq0MKPAEePNiDAo5NHBQRoRMJH7SXfqYh_kjZ0-Pi`
(`local://foundation-expansion-sheenbidi-external-driver-package-fetch-322.log`).
Two further gates ran **inside that materialised copy**:

* `sha256sum -c UPSTREAM.sha256` — exit 0, the same 218 records, every line
  `<path>: OK`, nothing failed and nothing missing
  (`…-sheenbidi-materialized-package-integrity-331.log`). This is what turns
  entry 10's "works in a package a dependent fetched" into a run: all 218
  records — `Headers/`, `Source/`, `Tools/`, `Tests/`, upstream's two build
  systems and their `.in` templates, `LICENSE` and `README.md` — are files
  `.paths` delivers, so `.paths` is complete against the record and not only
  against this tree.
* `consumer/` in the fetched copy, `zig build run` — exit 0
  (`…-sheenbidi-materialized-package-consumer-338.log`). Its receipt is **empty**,
  so it establishes that the program built, linked and exited 0 and nothing
  about what it printed; the values it checks are the ones quoted from its own
  source under [Examples](README.zig.md#examples), as with the in-tree consumer.

**Separately proven, and not part of this entry.** `git diff --exit-code
cfe430e7375a7845b679adae9d51dac6deaa8858 -- Headers Source Tests Tools LICENSE
CMakeLists.txt Makefile meson.build meson_options.txt` exits 0 with empty
output (`…-sheenbidi-pinned-native-pristine-diff-265.log`): the native bytes
this fork ships are the pinned commit's bytes. That is a direct diff of **this**
working tree — not a replay of `git archive`, not a CI run, and not something
the materialised copy restates, since that copy is not a Git clone.

**What this entry does not close.** The fetch source was this local directory,
so no remote URL, no registry index and no published `.hash` was exercised, and
no publication is authorized. The `git archive` replay in
[Not observed](README.zig.md#not-observed) is still not run: closing it needs a
re-fetch of upstream, which this workspace does not have, and neither the
materialised-package integrity row nor the pinned-native diff stands in for it.
Entry 3's `-fsys=sheenbidi` remains ungated and unclaimed. One earlier attempt
at materialising this package failed with `IllegalFileTypeInPackage` over the
directory (`…-sheenbidi-materialized-package-fetch-258.log`); the runs above
supersede it and it is kept here as history, not as current state.


## 17. Flush the consumer's buffered output; do not assert an unassigned licence

The earlier materialised consumer exited 0 with an empty receipt (338): its
assertions ran, but its 4096-byte stdout buffer was never flushed. `main` now
calls `try w.flush()` after the final row-45 confirmation. The working-tree
consumer (438) and filtered-package consumer (444) both exit 0 and print the
14-codepoint visual order and all four mirrors. The filtered fetch at 440 and
218/218 digest replay at 443 cover that source change; their package identity
names that observed snapshot, not later documentation edits.

The manifest's package-wide `.license = "Apache-2.0"` field is removed.
Upstream C code remains Apache-2.0 and the Unicode inputs retain their own
terms. Neither grant is asserted over the fork-authored files: their licence
is the owner's unassigned decision, as recorded in `NOTICE.md`.


## 18. Joined the published 53-platform `cross-test` matrix

**Condition.** `zig build check` answers six compile-only questions. The
workspace gate for the eight additions is the published Zig 0.16.0 Tier 1/2
matrix, 53 platforms, run by `~/.local/bin/cross-test`, and a cell of it is a
real `zig build test -Dtarget=TARGET` rather than a compile. Nothing in this
package could be selected by that harness, because a harness that is meant to
discover settings needs a settings file and this package had none.

**Change.** A new `cross-test.profile.sh` at the package root: four ordinary
Bash variable definitions, `CROSS_BUILD_STEP=test`, `CROSS_BUILD_JOBS=2`,
`CROSS_BUILD_TIMEOUT=3600` and `CROSS_TIMEOUT=1800`. No `cross_build_command`,
no `cross_artifact`, no `CROSS_MATRIX`, no `TARGETS` and no host path, so the
harness keeps the standard Zig-build mode, keeps the full published matrix and
keeps its own runner policy, and every value stays a default the command line
overrides. `CROSS_LIBC_RUNTIMES` is deliberately absent: it names foreign libc
loaders on the machine running the harness, which is that machine's business.
The file is listed in `build.zig.zon`'s `.paths`, so a fetched package carries
it, and `NOTICE.md` records it among the fork-authored files whose licence is
unassigned — upstream's Apache-2.0 does not reach it.

**What was not changed.** No `build.zig` line, no native source, no test and no
fixture. The `test` step already attached a run artifact per mode
(`build.zig:329-340`), which is what lets a cell with a runner execute all
nineteen tests and a cell without one still compile them; the harness replaces
the run step's action with a skip and leaves the compile dependencies in place
(`run_policy.zig:55-57`, `:103-105`), so an unrun cell is `build_only` and not a
pass. Nothing was skipped to make that true: the two UAX #9 replays, the
representative check against `DerivedBidiClass.txt` and the sixteen boundary
cases are the same nineteen on every cell.

**Accounting, stated so it is not misread later.** One cell that runs reports
`38/38 tests passed`, and that is nineteen in Debug plus the same nineteen in
ReleaseSafe from a single `zig build test` — the same aggregate the native
receipts in entry 15 already record. It is never "38 in Debug".

**Status: observed.** The full 53-platform matrix ran on 2026-10-02. The final
sweep is `cross-test --jobs 2 --build-jobs 2 --build-timeout 3600` from this
directory, run id `20261002-062101-65268-4429`, `--test-timeout 1800s` per cell,
with `cross-test.profile.sh` sourced and no command-line override of the
deadlines it sets. All 53 published targets were covered and the harness exited
**0**: **20 pass, 33 build_only, 0 fail**, `status: partial` because a
`build_only` cell is not a pass. The twenty passing cells are each
`Build Summary: 11/11 steps succeeded; 38/38 tests passed`; the thirty-three are
each `Build Summary: 9/11 steps succeeded (2 skipped)`, the two skipped steps
being the harness's own run steps rather than any subset of the nineteen.
Receipts are `local://foundation-cross-test-final-sheenbidi-<target>.log`, one per
target. `tests.zig` still embeds `Tools/Unicode/BidiTest.txt` (7.6 MB) and
`Tools/Unicode/BidiCharacterTest.txt` (6.6 MB) into **each** of the two test
binaries, and a passing cell still replays 490 846 property rows (770 241
cases) plus 91 707 character rows per mode: the deadlines are now measured
against, not merely argued for.

**The first sweep, and what it does not prove.** An earlier run the same day,
`--build-jobs 4 --build-timeout 1800` (run id `20261002-040254-42806-17091`),
overrode the profile's own values and ended at 19 pass, 32 build_only, **2
fail**, harness exit 1: `x86_64-linux` and `aarch64-freebsd` both at
`per_build_timeout`, build `exit 124`, `run: not_run`. It is kept as history,
not as current state. Nothing in this package changed between the two sweeps,
and they also used different cache directories, so the deadline is a plausible
but **unisolated** explanation for the two timeouts; no cause is claimed.

**Named, and then not needed.** `Source/Core/ThreadLocalStorage.h:57-60` selects
`__thread void *` on every Clang target at the pinned C dialect, because
`-std=c90` leaves `__STDC_VERSION__` undefined and
`Source/API/SBBase.h:58-66` therefore takes the `USE_ATOMIC_BUILTINS` branch;
`Source/API/SBAllocator.c:24` includes that header unconditionally. A target
whose C compiler has no thread-local storage would fail to compile the unity
unit there. All 53 published targets compiled it and the twenty with a runner
executed it, so the assumption held everywhere this run could see. That is
bounded by this matrix and this compiler, not by every target Zig can name,
and no native file was changed — none needed to be.

**Not closed by this entry.** The profile is listed in `.paths`, but the
filtered `zig fetch` at receipt 440, the 218-record `sha256sum -c` inside that
copy at 443 and its `consumer/` at 444 all predate this file. No fetched copy
has yet been observed to contain `cross-test.profile.sh`; re-running that round
is scheduled after these documents freeze, and until it happens the `.paths`
entry is `SOURCE-CONFIRMED` from the manifest and proven by no receipt. CI has
not been executed either: `.github/workflows/verify.yml` is present and
unrun, so no publication, registry resolution or hosted-runner result is
claimed anywhere in this entry.

