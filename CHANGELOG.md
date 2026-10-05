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


## 19. Zig API contract alignment — 2026-10-03

**Condition.** `Source` borrows code units. Native retain/release relationships
do not retain those bytes, and Line does not retain its Paragraph.

**Fix.** State the source lifetime through the last derived object, each
retained parent, release and alias-copy duty. Document `.explicit = 125`
with its P2/P3 meaning, `visualOrder` allocation and errors, and a complete
consumer sequence. Correct stale native citations.

**Verification and bound.** Zig 0.16.0, native Linux x86-64: install,
Debug/ReleaseSafe tests, smoke, the separate package consumer and module
example pass. The published compile-only `check` matrix passes. This is not
a fresh 53-platform runtime result. Native and generated bytes are unchanged.

## 20. Preserved upstream's README as `README.upstream.md` — 2026-10-04

**Condition.** The fork needed a `README.md` of its own, in the canonical order
— native-source deviations, native-build deviations with dated history, the
matrix, consumption — while upstream's README carried the licence grant, the
copyright line and the object-model description this package cites by line
number.

**Fix.** Upstream's README is preserved byte for byte as `README.upstream.md`,
and `README.md` is the fork's. `UPSTREAM.sha256`'s record line changed name and
not digest (`34376a69…ae1c8`, the digest the driver's extraction receipt records
for the preserved file), so the count stays **218**. Every line citation moved
with the bytes: the grant is `README.upstream.md:169-184`, the copyright `:171`,
the object model `:45-69`, the dependency statement `:71-72`. `NOTICE.md`,
`UPSTREAM.md`, `README.zig.md` and `FORK-NOTES.md` were repointed; the build and
CI roles repointed theirs.

**Status: pending.** The record was updated and `sha256sum -c UPSTREAM.sha256`
has not been re-run since. The green run in the matrix predates the rename and is
evidence about the predecessor, not about this tree.

## 21. Gave the fork's own files an owner-authorized `Apache-2.0` grant — 2026-10-04

**Condition.** Entries 14, 17 and 18 withdrew an Apache-2.0 offer nobody had
made and recorded the fork's files as unassigned: upstream's grant does not
reach additions this fork made.

**Fix.** The owner authorized a per-project licence for the fork-authored
additions. This project's is `Apache-2.0`, matching upstream's primary term.
New `FORK-LICENSE.md` records the authorization, its date, the reason, the scope
and the three exclusions — upstream's own work, the eleven Unicode data files,
and the `.gitignore` append. No copyright identity is invented and no fork
addition is attributed to an upstream author. `NOTICE.md` now carries the
three-way split instead of two parts and an unassigned remainder, and the files
this migration authored carry `SPDX-License-Identifier: Apache-2.0`.

**Status: pending.** A licence fact, not a gate. Nothing was run.

## 22. Installed the licence and provenance closure with the artifact — 2026-10-04

**Condition.** A prefix install shipped a binary whose licence text sat three
directories away in the source tree, and the Unicode terms reached only whoever
had the repository.

**Fix.** `zig build install --prefix <dir>` and the Nix derivation install the
same document set under `share/doc/sheenbidi/` — `LICENSE`, `NOTICE.md`,
`FORK-LICENSE.md`, `README.md`, `README.upstream.md`, `README.zig.md`,
`UPSTREAM.md`, `UPSTREAM.sha256`, `CHANGELOG.md`, `FORK-NOTES.md` — and the
eleven Unicode data files unmodified under `share/doc/sheenbidi/unicode/`. The
link inputs a C consumer needs are still exactly the library and
`include/SheenBidi/`.

**Status: pending.** No install has been inspected since.

## 23. Added standalone Nix packaging — 2026-10-04

**Condition.** The SDK had no Nix packaging, and this wave requires a standalone,
sibling-free delivery with separate static and shared variants and a
lightweight development environment.

**Fix.** New `package.nix` is one source-only derivation, parameterised by
`linkage`, called by both `flake.nix` and `devenv.nix` through `pkgs.callPackage`.
It imports nothing from a sibling workspace, names no host account, store path or
absolute mount, downloads nothing, and adds no C flag of its own: `-std=c90`,
`-DSB_CONFIG_UNITY` and the absence of the experimental text API stay decided in
`build.zig`. `flake.nix` exposes `packages.<system>.static`, `.shared` and
`.default`, with `default` = `static`, this SDK's existing policy. Each output
also gets `lib/pkgconfig/sheenbidi.pc`, generated from upstream's own
`sheenbidi.pc.in` with that output's real paths substituted. Static is described
as a static library artifact and nothing more: SheenBidi calls `malloc`, `free`,
`memcpy` and `memmove`, so no configuration of this package yields a wholly
static executable.

**Superseded by entry 29.** The `lib/pkgconfig/sheenbidi.pc` this entry describes
was a second file, written by the derivation, and it no longer exists: the build
graph's own `lib/pkgconfig/SheenBidi.pc` is the only `.pc` this package installs.

**Status: pending.** Neither derivation has been evaluated or built.

## 24. Made devenv the canonical development environment — 2026-10-04

**Condition.** This repository sits on an NFS volume, and a devenv shell that
keeps `.devenv/` and both Zig caches in the working tree puts build state on a
network filesystem — which the workspace's storage policy forbids. Entering a
shell must also not compile the SDK.

**Fix.** New `devenv.nix`, `devenv.yaml` and `.envrc`. The shell holds tools
only — Zig 0.16.0 and pkg-config — and exposes this package's own build on
demand; entering it compiles nothing. State placement is the caller's: `TMPDIR`,
`DEVENV_HOME`, `XDG_RUNTIME_DIR` and the Zig caches are supplied on approved
local scratch, and `devenv.nix` adds no path of its own and erases none of them.
The nixpkgs input is pinned by commit and no file here writes a lock.
`.gitignore` grew entries for `/.devenv/`, `/.devenv.flake.nix`,
`/devenv.local.nix` and `/.direnv/`; `.envrc` and the two lock files are
deliberately not ignored. The exact task and output shape shipped is entry 27,
which corrected this one the same day before anything was gated.

**Superseded by entry 29.** A `flake.lock` is now present in this working copy, so
"no file here writes a lock" describes who may write one rather than what is in
the tree. The ownership rule itself — that both lock files belong to the
workspace driver — was not disturbed.

**Status: pending.** No shell has been entered under a gate.

## 25. Repointed the citations this migration moved — 2026-10-04

**Condition.** The build and CI roles rewrote `build.zig` (670 lines) and
`.github/workflows/verify.yml` (413 lines) for the linkage matrix, the delivery
job and the runtime configuration, which moved every line the
documentation cited into them.

**Fix.** In the documents that describe current state:
`build.zig:211` → `build.zig:441`, `build.zig:329-340` → `build.zig:631-648`,
`build.zig:291-296` → `build.zig:563-568`, and
`.github/workflows/verify.yml:57-58` → `:83-84`. Earlier entries citing the old
numbers are **not** rewritten: they describe the file as it stood, and this
entry is the record of the move. `CHANGELOG.md` entry 15's statement that the
workflow has three jobs is likewise history; the workflow now has five — `native`
with the linkage matrix, `delivery` over linkage × the four optimize modes
asserting the installed closure, `runtime` over the four `-Dlinkage` × `-Druntime`
cells, `cross`, and `consumer`.

**Status: pending.** Documentation and configuration only; nothing was run.

## 26. Named the one gap this migration leaves — 2026-10-04

`zig/root.zig:19` still says that the product of a `zig build` is
`libSheenBidi.a`. Under `-Dlinkage=dynamic` it is `libSheenBidi.so.3.0.0` with
its `libSheenBidi.so.3` and `libSheenBidi.so` links. That file belongs to the
facade role, which is not running for this SDK in this batch, so the correction
is recorded in [`FORK-NOTES.md`](FORK-NOTES.md) and raised with the driver rather
than made from the documentation seat. Everything the documentation seat owns
describes both artifacts.

## 27. Corrected the packaging interface to one injected derivation — 2026-10-04

Same day, same migration, before anything was gated. Four shapes were wrong and
are now the canonical ones:

* `package.nix` is an ordinary uncurried function with injected
  `lib`/`stdenv`/`zig` and `linkage ? "static"` returning **one** derivation. The
  static and shared variants exist only at the two entry points: flake
  `packages.<system>.static`/`.shared` (`.default` = static) and lazy devenv
  `outputs.static`/`outputs.shared`. Both call it through `pkgs.callPackage`.
* The derivation is install-only: `dontBuild`, `dontConfigure`, `dontCheck`, and
  **not** `dontInstall`, which would disable the hook's real install phase. One
  `zig build` runs, with `-j"${NIX_BUILD_CORES:-1}"`, one optimize selection,
  `-Dcpu=baseline`, `-Dlinkage=<variant>` and `--prefix "$out"`, and both Zig
  caches under the sandbox `TMPDIR` outside the unpacked source.
* `build.zig` is the sole writer of the installed closure. `postInstall` no longer
  re-installs the documents and the Unicode data; the only file the derivation
  adds is `lib/pkgconfig/sheenbidi.pc`.
* `devenv.nix` exposes the SDK build as namespaced `sheenbidi:*` tasks, not bare
  task keys, and no longer redirects `XDG_*` or the Zig caches from
  `HOST_SCRATCH_ROOT` or refuses to evaluate without it. State placement is the
  caller's: `TMPDIR`, `DEVENV_HOME`, `XDG_RUNTIME_DIR` and the Zig caches are
  supplied on approved scratch, and the file adds no path of its own and erases
  none. `devenv build outputs.static` is the real packaging route from a shell.

**Superseded by entry 29.** The last clause of the third bullet — that the only
file the derivation adds is `lib/pkgconfig/sheenbidi.pc` — is no longer true. The
derivation now adds no file at all, and the build graph's own
`lib/pkgconfig/SheenBidi.pc` is the only pkg-config metadata in a closure. The
rest of that bullet stands: `build.zig` was and remains the sole writer of the
installed closure.

The source filter was extended at the same time: version control, `.zig-cache`,
`zig-cache`, `zig-out`, `zig-pkg`, `.devenv`, `.devenv.flake.nix`, `.direnv`,
`result`, `result-*` and the two lock files are excluded; every source, fixture,
test and licence dependency stays.

**Status: pending.** Nothing was evaluated or built, before or after.

## 28. Corrected the runtime documentation to the build's own spelling — 2026-10-04

The runtime switch is `-Druntime` (bool, default false). `README.md` and
`README.zig.md` said `-Druntime-loading=true`; `b.option` rejects an unknown
`-D`, so the documents named a switch that does not exist. Fixed, and three
build-graph facts folded in while the text was open:

* **Delivery is a two-by-two matrix, not a third product.** `-Dlinkage` decides
  the artifact — `lib/libSheenBidi.a`, or `libSheenBidi.so.3.0.0` with the
  `.so.3` and `.so` names and SONAME `libSheenBidi.so.3`, upstream's own
  `CMakeLists.txt:143-147` — and on Windows `bin/SheenBidi.dll` with
  `lib/SheenBidi.lib`. `-Druntime` changes only what the facade is bound to and
  never what is installed. All four pairings are built by CI; the runtime +
  static cell loads a shared object from a separate `-Dlinkage=dynamic` build of
  this same source tree, which is the compatible-external-provider case, not a
  contradiction.
* **`bin/misuse` is installed in every configuration**, and CI runs three
  observations against all four cells: `pre-load` stops, `after-load <path>`
  succeeds, `linked-load` stops. `zig build` names no provider, so
  `zig build test -Druntime=true` stops with `smoke.zig`'s own message naming
  `SHEENBIDI_PROVIDER` and `--provider <path>` instead of passing vacuously.
* **The ABI section was wrong in two places and is now the loader's own text.**
  `SBCodepointSequence`, `SBAllocatorProtocol`, `SBRun`, `SBScriptAgent` and
  `SBMirrorAgent` all cross the boundary **by pointer** — they do not cross by
  value as this package's documents said — and `SBUInteger`/`SBInteger` are
  `uintptr_t`/`intptr_t`, so widths follow the target rather than the provider's
  build host. A provider must export all fifty-one public functions and no data;
  which Unicode revision its tables came from is explicitly **not** a
  requirement. `runtime/library.zig` is the source of that list and this
  package's documents now point at it instead of restating it.

**Prerequisite, resolved by entry 29.** `runtime/graph.zig` names
`runtime/loader.zig` and `runtime/generate.zig`, and `runtime/library.zig` names
`runtime/sync.h`. When this entry was written those core files were not in the
tree, which is the reason it gave for `-Druntime=true` not being able to
configure. All four are in the tree now, so that stated reason no longer holds.
Whether `-Druntime=true` in fact configures, compiles, runs `bin/misuse` and
executes `SHEENBIDI_PROVIDER` is still `PENDING-VERIFICATION`: no gate in this
workspace has run any of it, and this entry does not substitute for one.

**Status: pending.** Nothing was run.

## 29. Gave the build graph sole ownership of the installed pkg-config file — 2026-10-04

**Condition.** `build.zig`'s `addPkgConfig` already wrote and installed
`lib/pkgconfig/SheenBidi.pc` (`build.zig:944`, `:977`), and `package.nix`'s
`postInstall` wrote a second file, `lib/pkgconfig/sheenbidi.pc`, from the same
upstream template. Both carried `Name: SheenBidi` and `Libs: -lSheenBidi`; the
base names differed only in case. The two disagreed on the one field that depends
on the variant: `build.zig:972` appends ` -DSB_CONFIG_DLL_IMPORT` to `Cflags:`
under `-Dlinkage=dynamic`, where the derivation substituted
`@SHEENBIDI_PKGCONFIG_CFLAGS@` with nothing. `nix build .#shared` therefore
described a shared library without the decoration its headers require on
`_WIN32`, and `pkg-config` answered according to the spelling it was asked for.
Every document that described the delivery repeated the opposite claim — that
`build.zig` generates no `.pc` and the derivation adds the only one — and
`package.nix`'s own comment said so too. That is what kept the duplicate
invisible: the docs agreed with each other and disagreed with the build graph.

**Fix.** `postInstall` is deleted from `package.nix`; the derivation has no
file list and adds nothing, so there is no second writer and no second place in
which an installed path can be described wrongly. The reason it needed no prefix
fixing is that `build.zig` writes `prefix` as `${pcfiledir}/../..`, relative to
the `.pc` file pkg-config found, so a fixed `$out` is a prefix like any other to
it. The installed name is `SheenBidi.pc`, capitalised, because the base name is
`library_name` — the same string `linkSystemLibrary` is asked for. Corrected in
`README.md` (§ As a C library, § Through Nix, § Through devenv),
`README.zig.md` (§ The installed C contract, § devenv is the canonical
development environment, § Nix is the delivery), `NOTICE.md` (the `.gitignore`
row, the `build.zig.zon` row and the installed-closure block), `CHANGELOG.md`
(entries 23, 24 and 27 above, each carrying a pointer) and `FORK-NOTES.md`
(M4 and M5).

**Runtime staleness corrected in the same pass.** Entry 28 recorded the loader
core as not yet in the tree; `runtime/loader.zig`, `runtime/generate.zig`,
`runtime/sync.c` and `runtime/sync.h` are all in it now, and
`-DRT_SYNC_PREFIX=sheenbidi_rt` (`runtime/graph.zig:48`, `:217`) binds `sync.c`
here. That paragraph above has been corrected rather than preserved as history,
because it stated a present fact that is no longer true — a dated entry can
record what was believed when it was written, but this one asserted what is in
the tree, and a reader would take it as current.

**Lock staleness corrected in the same pass.** Every document that mentioned the
two lock files said only that they belong to the workspace driver and that no
file here writes one, which left the presence of one of them unstated. What is
actually true: a `flake.lock` is present in this working copy and pins `nixpkgs`
to the same commit `flake.nix` names; `devenv.lock` does not exist in this tree
and none is invented for it; and `flake.lock` ships in `build.zig.zon` `.paths`,
so a fetched copy carries the pin its flake declares. That `.paths` listing
landed later in this same pass, after the stale text was first corrected, so the
documents were briefly describing a tree that no longer existed; they now
describe the tree as it stands.

The ownership rule the documents recorded was never wrong and has not changed —
no file of this package writes either lock. What they got wrong was treating the
derivation's exclusion of the locks as a statement that a lock is not package
content. It is a different axis: `flake.lock` is package content and ships, and
the derivation drops it from `src` only because `zig build` never reads it, by
which time the Nix flake frontend has already resolved the locked inputs. That is
not a defect, and the documents no longer describe it as one.

**Status: pending.** Nothing was run. Every gate above the source-confirmed
descriptions is still `PENDING-VERIFICATION`, including the install and both
derivations that would show which `.pc` files a closure actually carries.

## 30. Moved readiness claims onto the 2026-10-04 receipts — 2026-10-04

**Condition.** The documents this migration rewrote were written before the
current round ran, and they still said of the whole tree that nothing had been
gated. Sixteen gates had in fact run between 15:09 and 15:20 UTC that
afternoon, all exit 0: `zig build test smoke install` across both linkages and
all four optimize modes, eight of them with `-Druntime=true`. Saying "no gate
has run" beside sixteen green receipts is its own kind of wrong.

**Fix.** The current-scope readiness rows in `README.md`, `README.zig.md`,
`NOTICE.md` and `FORK-NOTES.md` were moved onto those receipts, with the exact
scope read out of the receipts rather than summarised:

* `44/44 tests passed` per invocation, printed as `run test 22 pass (22 total)`
  twice — once for Debug, once for ReleaseSafe. The documents said 19 per mode
  and `38/38`; that was true on 2026-10-02 and `tests.zig` has since grown to
  **22** test blocks. Both figures are now labelled with their own date, and the
  arithmetic rule that made `38/38` a two-mode total is restated unchanged for
  `44/44`, because it is the part that stops a reader treating either as a
  single-mode count.
* `smoke` ran and asserted, closing on `every printed answer matched the
  published expectation` in both the `linked` and the `loaded` configuration.
* `install` ran, and its step summary names `install generated to
  pkgconfig/SheenBidi.pc` in all sixteen — the capitalised name entry 29 says
  is the only one. Two of those prefixes are still readable on disk:
  `sheenbidi-static/lib/pkgconfig/SheenBidi.pc` ends `Cflags:
  -I"${includedir}"`, and `sheenbidi-shared/lib/pkgconfig/SheenBidi.pc` ends
  `Cflags: -I"${includedir}" -DSB_CONFIG_DLL_IMPORT`. Both directories hold that
  one file and nothing else. **Entry 29's corrected `.pc` description is
  therefore observed, not merely source-confirmed** — including the per-variant
  Cflags difference the documents previously denied.
* The runtime route is exercised: the eight `loaded` receipts set
  `SHEENBIDI_PROVIDER` to a separately built `libSheenBidi.so`, each prints
  `configuration: loaded`, and the step tree shows the suite running under a
  generated dispatch. A successful load is a recorded fact. `README.zig.md` §
  What is not claimed said "nothing here has been run"; that is now narrowed to
  what genuinely has not.

**What was left pending, deliberately.** No `bin/misuse` observation ran — the
receipts record `install misuse`, not a run of it — so `pre-load`,
`after-load`, `linked-load`, retry, idempotence and provider-change stay
`PENDING-VERIFICATION`. So do the six-target check, the 53-platform matrix, the
integrity check, the installed C consumer against the new closure, `zig fetch`,
the devenv shell, and both Nix derivations. No Nix output has been built or
inspected, so entry 29's Nix-side claims stay source-confirmed only, and the
documented spelling difference between a prefix install and a Nix output remains
a prediction until a derivation runs.

**The run-step flag is not covered by these receipts.** `has_side_effects` is
set on the smoke and test run steps; the sixteen gates predate that change, so
they are not evidence for it. It needs its own focused proof — the same command
twice against one cache dir, showing the second run executes rather than being
served from the run cache. That is `PENDING-VERIFICATION` and is recorded as its
own row rather than being folded into the sixteen.

**Status: pending.** No gate was run to produce this entry. It corrects what the
documents claimed against receipts that already existed; it does not move a
gate.

## 31. Removed a `> 0` precondition the decoders never had — 2026-10-04

**Condition.** The two direct previous-decoders contradicted themselves in their
own documentation. `codepointDecodePreviousFromUtf8` and
`codepointDecodePreviousFromUtf16` each said `index` must be greater than `0`,
while the shared note nine lines above them — the one the `Next` pair also reads
— said an index of `0` or past the length is `codepoint_invalid` with the index
unchanged. Both statements cannot be true of the same parameter.

**Fix.** Comment text only, in `zig/root.zig:963-966` and `:982-985`. Each now
points at the shared note and says index `0` is out of range in the same way an
index past the end is, because nothing precedes the first code unit. **No code
line moved and no signature changed**: this corrects a documented precondition
that never existed. A reader who had taken the old comment literally would have
rejected a correct call.

**Upstream settles it, and was never in doubt.** `Source/API/SBCodepoint.c:283`
and `:345` both guard on `(*index - 1) < length`. At index `0` that subtraction
wraps unsigned, fails the guard, and the function returns `SBCodepointInvalid`
with `*index` untouched. `Headers/SheenBidi/SBCodepoint.h:145` and `:177` have
always said "or `SBCodepointInvalid` if `index` is zero or out of bounds". The
contradiction was in this fork's comments alone — `smoke.zig:244-247` and
`tests.zig:1206-1208` already passed index `0` and asserted `codepoint_invalid`
with the start index left at `0`, and `tests.zig:1209-1211` does `len + 1` for
UTF-16. The tests were right and the prose was wrong.

**Status: observed externally, not by this package's suite.** The driver ran a
disposable external consumer against the package — static, linked, native, no
provider and no arguments — not `zig build test` and not `smoke`. It passed 7/7,
and the seven are four boundary answers and three controls:

* index `0` on both direct previous-decoders returned the invalid sentinel with
  the index unchanged at `0`;
* index `0` on the sequence-form `codepointBefore` returned the same, which is
  the third boundary answer and the one that shows the contract is the
  sequence's and the decoders' alike, not an artefact of the direct pair;
* UTF-16 past the end returned the invalid sentinel with the index unchanged at
  `5`;
* and three controls did decode — U+05D0 starting at `5` (UTF-8), `3` (UTF-16)
  and `5` (`codepointBefore`).

The controls are what make the four boundary answers mean anything: without
them, an index-0 answer of `codepoint_invalid` would also be consistent with a
decoder that decodes nothing at all.

This package's own `zig build test` and `smoke` were **not** re-run for this
slice. The sixteen 2026-10-04 receipts recorded in entry 30 above predate the
comment edit, and a comment-only change cannot alter behaviour; that is an
argument, not a receipt, and the next full gate is what closes it. No new
permanent test was added: `tests.zig` and `smoke.zig` already assert every one of
these cases, so a new test would only restate them.

## 32. Made every canonical devenv task locate this checkout itself, and kept its output off it — 2026-10-04

**Condition.** `devenv.nix` is entered with `--from path:<this SDK>`, and devenv
generates each task wrapper with the *project* directory as its working
directory. `DEVENV_ROOT` names that project, and `devenv tasks run` does not run
`enterShell`, so a task that trusted either was looking for `build.zig`,
`UPSTREAM.sha256` and `consumer/` in a directory that holds none of them. The
2026-10-04 acceptance run observed exactly that, from a `devenv.nix` that parsed
and whose seven task names all loaded:

* `…-sheenbidi-devenv-consumer.log` — `line 3: cd: consumer: No such file or directory`;
* `…-sheenbidi-devenv-integrity.log` — `sha256sum: UPSTREAM.sha256: No such file or directory`.

Both are wrapper failures and neither ran `zig`: the exit status is the `cd` and
the `sha256sum`, not a build.

**Fix.** `devenv.nix` evaluates `./.` — the directory of the file that writes it
— once, through `builtins.toString`, and quotes it with
`pkgs.lib.escapeShellArg`. `sdkRoot` and `consumerRoot` are the first line of
every task: `build`, `test`, `smoke`, `check`, `install` and `integrity` change
into the checkout, `consumer` into `consumer/`. No task name changed and no
caller flag moved — `"$@"`, `-j8`, `--summary all` and `-Doptimize=ReleaseSafe`
are forwarded exactly as before. Whether Nix renders that string as this
working tree or as a store copy of it is a property of how a path literal
stringifies rather than of this expression; no run has observed which, and
either rendering contains the files these tasks read.

**Where build output goes.** `sheenbidi:build` runs the default step, and that
step *is* the install step: `build.zig:979` attaches `SheenBidi.pc` to
`b.getInstallStep()`, and the library, the headers and the licence records are
attached there too. Left alone it wrote `zig-out/` into this NFS checkout. It
now installs to `$ZIG_LOCAL_CACHE_DIR/sheenbidi/build`, and `sheenbidi:install`
to `$ZIG_LOCAL_CACHE_DIR/sheenbidi/install`. Both derive that root the same way:
the exported `ZIG_LOCAL_CACHE_DIR`, else `$XDG_CACHE_HOME`, else `$TMPDIR`, and
with none of the three they name the variable to set and exit non-zero. The old
`$TMPDIR` default and its `/tmp` fallback are gone — a small system temporary
filesystem is not approved storage.

`test`, `smoke`, `check` and `consumer` keep no `--prefix` deliberately: their
steps depend on test, run and compile steps only (`build.zig:1232`, `:1203`,
`consumer/build.zig:79`) and never on `b.getInstallStep()`, so they install
nothing and have no output to redirect. A caller's own `--prefix`, arriving in
`"$@"`, still overrides both defaults exactly as it did before.

**Status: pending.** This is a source-only change. No devenv gate has run since
it landed, so this entry claims the edit and the two receipts above, and says
nothing about any task's exit code afterwards.

## 33. Fixed the last task's job count and gave every build an external cache — 2026-10-04

**Condition.** Entry 32 made every task locate this checkout and moved the two
installing tasks' output off it. Two things were still open. The job count:
`sheenbidi:build` ran `zig build --prefix "$scratch/build" --summary all "$@"`, so
the default install step took its parallelism from whatever the machine offered,
while `test`, `smoke`, `check`, `install` and `consumer` already passed a literal
`-j8` — it was the only `zig build` in this file without one. And the cache: no
task named `--cache-dir`, and only `build` and `install` ran the snippet that
resolves a scratch root, so `test`, `smoke`, `check` and `consumer` reached zig
with neither `--cache-dir` nor `ZIG_LOCAL_CACHE_DIR` set, and the only other place
this file could export one is `enterShell`, which `devenv tasks run --mode
single` does not run. A `zig build` in that state keeps `.zig-cache/` at its own
build root — this checkout for four of them, `consumer/`'s for the fifth — which
is the state `README.zig.md` used to document as what a task leaves behind.

**Change, one: the job count.** `zig build --cache-dir "$ZIG_LOCAL_CACHE_DIR"
--prefix "$scratch/build" -j8 --summary all "$@"`. The flag sits after `--prefix`
and before `--summary all` and `"$@"`, the order `install` already used, and a
caller's own flag in `"$@"` is still the last word. The other five command lines
are unchanged apart from the `--cache-dir` below.

**Change, two: the cache.** The snippet `scratchRoot` names is kept, with the
same root order — the exported `ZIG_LOCAL_CACHE_DIR`, else `$XDG_CACHE_HOME`, else
`TMPDIR`, no `/tmp` fallback — and the same non-zero exit naming the variable to
set when none of the three is exported. It now also fills a missing
`ZIG_LOCAL_CACHE_DIR` with `$scratch/cache`, fills a missing
`ZIG_GLOBAL_CACHE_DIR` with `$XDG_CACHE_HOME/zig` else `$TMPDIR/zig` (and exits
non-zero naming that variable when it has neither), creates both and exports
both — in the task body, ahead of the compiler, because `devenv tasks run` does
not run `enterShell`. All six `zig build` bodies then pass
`--cache-dir "$ZIG_LOCAL_CACHE_DIR"`, which is the same directory that snippet
left in the environment, so the flag and the variable cannot disagree. A caller
that exported either variable keeps its own value: the snippet fills only what is
missing. `test`, `smoke`, `check` and `consumer` run the snippet now, where
before they did not; `build` and `install` already did.

**What did not move.** No task name, no step name, no `"$@"`, no `--prefix`
target, no cache *root* choice. The `--prefix` still goes to `build` and
`install` alone, because only those two steps reach `b.getInstallStep()`
(`build.zig:979`); the other four install nothing and are still given no prefix,
which is a delivery output and not a cache. `integrity` runs `sha256sum -c
UPSTREAM.sha256`, starts no compiler and is untouched.

**Boundary.** `devenv.nix`, this entry and two paragraphs of `README.zig.md`.
No `build.zig`, `package.nix`, flake, header, source, test, fixture, Unicode data
or licence record changed, and `-Dlinkage`, `-Doptimize`, `-Druntime` and `-fsys`
keep the defaults this package already had. `devenv tasks run` on devenv 2.4
takes no trailing argument, so `"$@"` is empty on that route: nothing here claims
a caller-supplied flag or cache variable was exercised through it.

**Status: source-only.** No devenv gate has run since this edit, so this entry
claims the diff and says nothing about any task's exit code afterwards.

## 34. Resolved the host before dispatching, so `-fsys=sheenbidi` cannot bind a host library to a foreign target — 2026-10-05

**Condition.** `-fsys=sheenbidi` names a library installed on this machine, so
it can only mean a target this machine is — entry 3's rule and
[`FORK-NOTES.md`](FORK-NOTES.md) §4's. `std.Target.Query.isNative()` cannot
answer that question: it is false for every *named* target, so it reports
"was `-Dtarget` spelled out?" and never "is this the machine?". The graph
therefore resolves the host rather than inferring it.

**Change.** One function, `isThisMachine` (`build.zig:762-770`), reads
`b.graph.host.result` — the resolved host's architecture, operating system and
ABI — and compares all three with the resolved target's. `build` calls it
before it dispatches, and `@panic`s with a named message when `-fsys=sheenbidi`
and a foreign `-Dtarget` are combined (`build.zig:1069-1073`): "`-fsys=sheenbidi`
names a library installed on this machine; it has no meaning for a foreign
`-Dtarget`". The wrong host is never selected, so nothing downstream is asked
to bind a host image to a target it was not built for.

**What did not move.** `check`'s own dispatch still asks
`target.query.isNative()` (`build.zig:1263`), because that is the *other*
question — "was a target named, so answer it rather than also answering five
nobody asked?" — and it stays as it was. No option, default, step name,
artifact, install path, C flag, header, source, test, fixture, Unicode file or
licence record changed; `isThisMachine` is called from one place, and
`use_system` keeps its own meaning.

**Status: pending.** No receipt in this package was taken after this edit, so
no gate has looked at the guard. Every row in
[`README.zig.md`](README.zig.md#verification-status) that predates it is
evidence about the tree as it stood before it, and none of them is a result for
the guard. `-fsys=sheenbidi` itself remains ungated at compile time and at run
time, exactly as entry 3 left it and as
[`README.zig.md`](README.zig.md#not-observed) still records.
