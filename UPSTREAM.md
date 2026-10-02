# UPSTREAM.md — what this fork is a fork of

## Upstream

| | |
|---|---|
| Project | SheenBidi, a C implementation of the Unicode Bidirectional Algorithm (UAX #9) |
| Canonical repository | `https://github.com/Tehreer/SheenBidi.git` |
| Pinned ref | tag `v3.0.0` |
| Pinned commit | `cfe430e7375a7845b679adae9d51dac6deaa8858` |
| Version of the C library built here | `3.0.0` |
| Library licence | `Apache-2.0` |
| Data-file licence | the Unicode terms named by the files themselves (see [Unicode data](#unicode-data-terms)) |
| Copyright | Copyright (C) 2014-2026 Muhammad Tayyab Akram |

Where each of those comes from, read out of the carried tree:

* The version is `Headers/SheenBidi/SBVersion.h:24-27`
  (`SHEENBIDI_VERSION_MAJOR 3`, `MINOR 0`, `PATCH 0`, `STRING "3.0.0"`), and
  that string is what `SBVersionGetString()` returns at run time. It is the
  version of the C library, not a version of the Zig wrapper, and it is what
  `build.zig.zon` carries in `.version`. `build.zig:291-296` parses that field
  and `@panic`s if it stops matching the pin above, so a version bump is a
  decision someone has to make rather than a side effect of a merge.
* The licence is `LICENSE`, the Apache License 2.0 in full, and it is restated
  in `README.md:169-184`. The same grant heads 90 of the 98 files under
  `Headers/` and `Source/`; the year range in those per-file headers is
  upstream's own and varies between files (`Source/SheenBidi.c:2` says
  2014-2026, `Headers/SheenBidi/SheenBidi.h:2` says 2014-2025,
  `Headers/SheenBidi/SBVersion.h:2` says 2025-2026). Nothing here harmonises
  them, because these are upstream's bytes. The eight files with no header are
  the generated UCD tables in `Source/Data/`, which upstream's generator writes
  with a `DO NOT EDIT!!` banner and no licence line. The grant covers them
  anyway, because it covers the package rather than the file, and a per-file
  attribution audit needs them named as the exception — see [`NOTICE.md`](NOTICE.md).
* The copyright line "Copyright (C) 2014-2026 Muhammad Tayyab Akram" is
  `README.md:171`.
* Upstream describes the object model the facade wraps in `README.md:45-69`:
  `SBCodepointSequence`, `SBAlgorithm` (P1, P2-P3), `SBParagraph` (X1-I2),
  `SBLine` (L1-L2), `SBRun`, `SBMirrorLocator` (L4) and `SBScriptLocator`
  (UAX #24).
* The dependency statement in `README.md:71-72` is that SheenBidi needs only
  `stddef.h`, `stdint.h`, `stdlib.h` and `string.h` from the C library. That is
  why every module in this package is built with `link_libc = true` and why
  there is no other dependency anywhere in the graph.

**Tag signature: not verified here.** No signing key was consulted while this
file was written and no git command was run at all, so nothing here is an
observation of the clone's own state. Treat the commit id and the archive digest
below as the provenance anchors, not as a signature check.

## Archive receipt

The workspace delivery record `local://foundation-expansion-source-archives.json`
holds a SHA-256 receipt for the deterministic `git archive` stream of the **full
tree** at that commit. For this library it reads, verbatim:

```
9bdf0c279f5070f9d397d8f1446acd0bf8eebb802da80ca4cb6b57fb1cac4a28  -
```

The trailing `-` is `sha256sum`'s name for standard input: the digest is of the
archive stream as it was piped past the hasher, not of any file in this
repository. The driver produced it when the fork was imported. It is recorded
here so a later re-fetch can be compared against the same bytes.

The companion record `local://foundation-expansion-sources.json` names the same
repository, ref and commit, and records the licence as "Apache-2.0 plus Unicode
data terms". That phrase is the reason this document has a section of its own
for the data files.

## Import mechanism

A full clone of the canonical repository, so upstream's Git history is present.
The workspace delivery record states that every fork in this wave keeps the
upstream remote named `upstream`, a local `main`, and complete upstream history.
This fork adds no patch series on top of that history: the Zig package is a set
of new files in new regions, and the one upstream file that is edited at all is
`.gitignore`, which gains appended ignore entries (see [`NOTICE.md`](NOTICE.md)).

## What this fork is

A Zig package that compiles upstream's own C library from `Source/` in this
repository and publishes a Zig facade over the translated
`Headers/SheenBidi/SheenBidi.h`. Nothing of the bidirectional algorithm is
reimplemented, re-derived or reconfigured: no table is regenerated, no upstream
source is patched, and nothing is downloaded at build time. `NOTICE.md` lists
every file this fork adds or edits.

### What is compiled, and with which switches

One translation unit: `Source/SheenBidi.c`, upstream's own unity build, with
`-std=c90 -DSB_CONFIG_UNITY`. The unity file `#include`s all **32** checked-in
`.c` files under `Source/`: 15 API units, 4 core units, 4 generated UCD tables,
the script stack, 2 text-support units and 6 UBA run units. That is upstream's
default configuration, not a choice this fork made: `CMakeLists.txt` has
`option(SB_CONFIG_UNITY "Build with a single unity source file" ON)` and
`meson_options.txt` says `unity_mode = enabled`. The list is deliberately one
entry long — a glob or a per-file list would let a unit be added to or dropped
from the archive without a decision.

`SB_CONFIG_EXPERIMENTAL_TEXT_API` is **not** defined, so `SB_TEXT_API_SUPPORTED`
is 0 and the three text units contribute no definitions. That is upstream's own
default as well (`Headers/SheenBidi/SBConfig.h:39` ships the macro commented
out), and it is why the experimental text API is absent from the archive rather
than stubbed: there are no symbols to stand in for.
`SB_CONFIG_ALLOW_NON_ATOMIC_FALLBACK` is not defined either, so a threaded
target gets real atomics rather than a silent data-race-friendly fallback.

`-std=c90` is not cosmetic. `Source/API/SBBase.h` and
`Source/Core/ThreadLocalStorage.h` select their atomics and TLS backend from
`__STDC_VERSION__`: at C11 and above they take the `USE_C11_*` branches and
include `<stdatomic.h>`, below it they use the compiler-builtin `__atomic_*` and
`__thread` paths that need no platform header. All three of upstream's build
systems ask for C90 (`Makefile` passes `-ansi -pedantic`, upstream's
`linux.yml` passes `CMAKE_C_STANDARD=90` with extensions off and `-Dc_std=c89`
to meson), so pinning it keeps that decision identical on all six cross targets
this package claims.

### The Unicode data, and what is done with it

No table is generated at build time. `Source/Data/BidiTypeLookup.c`,
`GeneralCategoryLookup.c`, `PairingLookup.c` and `ScriptLookup.c` are
upstream's checked-in tables, generated by upstream's own `Tools/Generator` from
UCD 17.0.0, and they are compiled byte for byte.

`Tools/` is kept in this repository for two reasons: so the checked-in tables
can be traced to the data they came from and regenerated deliberately, and so
the two UAX #9 conformance fixtures travel with the package. `tests.zig`
`@embedFile`s three of them:

| Fixture | Size on disk | Used for |
|---|---|---|
| `Tools/Unicode/BidiCharacterTest.txt` | 6 880 771 bytes | the character conformance replay, 91 707 data rows |
| `Tools/Unicode/BidiTest.txt` | 7 959 988 bytes | the property conformance replay, 490 846 data rows → 770 241 cases |
| `Tools/Unicode/DerivedBidiClass.txt` | 173 433 bytes | checking the Bidi_Class representatives `BidiTest.txt` rows are turned into |

The remaining eight files in `Tools/Unicode/` (`BidiBrackets.txt`,
`BidiMirroring.txt`, `DerivedCoreProperties.txt`, `DerivedGeneralCategory.txt`,
`PropList.txt`, `PropertyValueAliases.txt`, `Scripts.txt`, `UnicodeData.txt`)
are upstream's generator inputs. This build compiles none of `Tools/`, and no
step of it runs `Tools/Generator` or `Tools/Parser`.

### Unicode data terms

The eleven files in `Tools/Unicode/` are Unicode, Inc. data files, not
SheenBidi source, and they are not covered by the Apache-2.0 grant. Ten of the
eleven carry their own terms in their own first lines; `UnicodeData.txt` is the
exception and begins directly with data rows. Verbatim, from
`Tools/Unicode/BidiCharacterTest.txt:3-5`:

```
# © 2025 Unicode®, Inc.
# Unicode and the Unicode Logo are registered trademarks of Unicode, Inc. in the U.S. and other countries.
# For terms of use and license, see https://www.unicode.org/terms_of_use.html
```

Ten of the eleven also name their own revision in their first line, for example
`# BidiCharacterTest-17.0.0.txt` and `# Date: 2025-07-30`. `UnicodeData.txt`
names none at all — no revision, no date, no copyright; its first line is a data
row — so its 17.0.0 provenance is inferred from the ten files beside it and
from the checked-in `Source/Data` tables generated from the same revision, not
read out of its own bytes.

This fork does not restate those terms, does not paraphrase them and does not
relicense them. The files travel unmodified, they keep the notice the Unicode
Consortium put in them, and the terms that govern them are the ones those lines
name. The Apache-2.0 text in `LICENSE` covers the SheenBidi library, its
headers, its tools and its tests; it does not reach these eleven files, and
nothing in this repository claims that it does. `NOTICE.md` records the same
split.

## What is upstream's and is shipped unmodified

Everything named in `build.zig.zon` `.paths` that this fork did not write:

| Path | What it is |
|---|---|
| `Headers/` | upstream's 23 public headers, including the aggregate `SheenBidi/SheenBidi.h` that `zig/translate.h` includes and the build installs |
| `Source/` | the whole C library: the 32 translation units the unity file pulls in, their headers, and the four generated UCD tables |
| `Tools/` | upstream's UCD 17.0.0 inputs, parser and table generator, and the two UAX #9 conformance fixtures |
| `Tests/` | upstream's own C++ test suite, kept whole. This build does not compile it; it is kept so a re-sync has something to diff against |
| `CMakeLists.txt`, `Makefile`, `meson.build`, `meson_options.txt`, `SheenBidi.cmake.in`, `sheenbidi.pc.in` | upstream's two build systems and their templates, kept for the same reason |
| `LICENSE` | the Apache License 2.0 text, verbatim |
| `README.md` | upstream's project README, which carries the licence grant (`README.md:169-184`) |

`.gitignore` is upstream's file too, and it is in `.paths`, but the fork appends
to it; see [`NOTICE.md`](NOTICE.md) and `FORK-NOTES.md` §1.

## What is carried but is not part of the package

`.github/workflows/linux.yml`, `macos.yml` and `windows.yml`, `.appveyor.yml`
and `.github/FUNDING.yml` stay in this repository for provenance and audit.
They are upstream's CI: they build upstream's CMake and meson projects with
upstream's text API enabled and they upload to upstream's Coveralls and
AppVeyor accounts. They are left exactly as they arrived and are not retargeted
at this fork's infrastructure. None of them is in `.paths`, none is referenced
by the build, and none is hashed by `UPSTREAM.sha256`; a dependent that fetches
this package will not receive them. This fork's own workflow is
`.github/workflows/verify.yml`, which is a new file and is also not in `.paths`.

## Integrity

`UPSTREAM.sha256` holds **218** records: the SHA-256 of every upstream file this
package ships, one `<hex>  <path>` line each, in `sha256sum` format. Check it
with:

```
sha256sum -c UPSTREAM.sha256
```

The path set is exactly the upstream-owned entries of `build.zig.zon` `.paths`:
`Headers/` (23), `Source/` (75), `Tools/` (60), `Tests/` (52), and the eight
root files listed above. Because the record names only files `.paths` ships,
the same command works in a cloned repository *and* in an unpacked package
fetched by a dependent. The `#`-prefixed header of the file explains, per path,
why anything is excluded; the exclusions are `.gitignore` (appended to, so not
byte-identical), this fork's own files, upstream's CI, and the record itself.

**How the digests were produced.** Each file was read as raw bytes with Bun's
`Bun.file(path).arrayBuffer()` and hashed with `crypto.createHash("sha256")`
from `node:crypto`, on 2026-10-01. No receipt in this package's set reports the
hashing tool's version, so this states the method and claims no version of it.
No shell hashing command and no git command was used to produce them. Every one
of the 218 records was then re-derived from the written file with the same
method and compared against it before this document was written; 218
re-derived, 0 mismatches. The tree walk also reported no symlinks and no
non-regular entries under the four hashed roots, so every record is the digest
of the file's own bytes.

**What the record establishes.** The bytes a build compiles and the fixtures its
tests read are the bytes this record pins, and any later edit to one of those
218 files fails the check loudly.

**What it does not establish.** It is not a signature, not a Git object id, and
not a re-derivation from commit `cfe430e7375a7845b679adae9d51dac6deaa8858`: it
is a hash of this working tree. That the tree equals that commit rests on the
import and on the archive digest above, both of which the driver recorded, not
on anything computed while writing this file. Replaying the check against
upstream is the driver's job and needs a re-fetch:

```
git -C <clone> archive --format=tar cfe430e7375a7845b679adae9d51dac6deaa8858 | sha256sum
```

The output must read `9bdf0c279f5070f9d397d8f1446acd0bf8eebb802da80ca4cb6b57fb1cac4a28  -`.
The second half of that recipe is already observed: `sha256sum -c UPSTREAM.sha256`
was run in this workspace and is green. The first half has not been.

**Status: observed.** The driver ran `sha256sum -c UPSTREAM.sha256` against this
tree: exit 0, 218 lines of output, every one of them `<path>: OK`, no failure and
no warning. Receipt
`local://foundation-expansion-sheenbidi-immutable-source-integrity-120.log`; the
gate is the first row of the matrix in
[`README.zig.md`](README.zig.md#verification-status). The same check runs in CI
at `.github/workflows/verify.yml:57-58`, unconditionally, as the `native` job's
"Immutable source and Unicode fixture integrity" step, ahead of `zig build`.

## Synchronising with a new upstream release

1. `git fetch upstream`, check out the new tag, and read
   `Headers/SheenBidi/SBVersion.h`'s `SHEENBIDI_VERSION_STRING`; that string,
   not the tag spelling, is the version.
2. Replace the upstream files in place: `Headers/`, `Source/`, `Tools/`,
   `Tests/`, the six build files, `LICENSE` and `README.md`. Do not hand-patch
   upstream source to make a build problem go away.
3. Re-read the licence grant in the new `README.md` and the notice in each data
   file, and re-read `CMakeLists.txt` and `meson_options.txt` for the default
   configuration the build quotes in its own comments.
4. Regenerate `UPSTREAM.sha256` over the same path set with the same method and
   update the count in its header comment and in this file.
5. Re-check the Unicode revision: `Tools/Unicode/*.txt` and the tables in
   `Source/Data/` move together, and the row counts in `tests.zig`
   (`bidi_character_test_rows`, `bidi_test_rows`, `bidi_test_cases`) are
   properties of the fixtures, not of the library, so a UCD bump moves them.
6. Bump `.version` in `build.zig.zon` to the new string, update the pin in this
   file and in `README.zig.md`, and add one numbered `CHANGELOG.md` entry.

## See also

* [`NOTICE.md`](NOTICE.md) — attribution, the licence split, every file this
  fork adds or edits, and the Apache-2.0 obligations that apply.
* [`README.zig.md`](README.zig.md) — how to build, import and call the package,
  and where the authoritative gate matrix lives; every gate this file reports a
  status for is described there rather than repeated here.
* [`CHANGELOG.md`](CHANGELOG.md) — numbered fork-only divergences.
* [`FORK-NOTES.md`](FORK-NOTES.md) — the problems met while doing this, and
  what was decided.
* [`UPSTREAM.sha256`](UPSTREAM.sha256) — the integrity record itself.
