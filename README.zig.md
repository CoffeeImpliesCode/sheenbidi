# sheenbidi — the Unicode Bidirectional Algorithm, built and wrapped in Zig

This package compiles SheenBidi **3.0.0** — upstream's own C, byte for byte,
from the `Source/` tree in this repository — and publishes a Zig facade over the
translated `Headers/SheenBidi/SheenBidi.h`. The algorithm is not reimplemented:
no table is regenerated, no upstream source is patched, and nothing is
downloaded at build time. The only dependency is a C compiler and libc, and
`build.zig.zon` declares no Zig dependencies at all.

Upstream: `https://github.com/Tehreer/SheenBidi.git`, tag `v3.0.0`, commit
`cfe430e7375a7845b679adae9d51dac6deaa8858`. Provenance, licences and the
integrity record are in [`UPSTREAM.md`](UPSTREAM.md), [`NOTICE.md`](NOTICE.md)
and [`UPSTREAM.sha256`](UPSTREAM.sha256).

## Requirements

Zig **0.16.0** — the real compiler, not the bare `zig` on `PATH`, which in the
workspace that grew this package is a version dispatcher; through the dispatcher
the command is `zig 0.16.0 build`. Plus a C compiler and libc, both of which
Zig supplies. Nothing is fetched.

The core needs the C library headers `stddef.h`, `stdint.h`, `stdlib.h` and
`string.h` and nothing else, which is upstream's own dependency statement
(`README.md:71-72`).

## Commands

| Command | What it does |
|---|---|
| `zig build` | compiles the C core, installs `zig-out/lib/libSheenBidi.a` and `zig-out/include/SheenBidi/*.h`, and compiles the example (not run) |
| `zig build --prefix <dir>` | the same install into a directory of your choosing — the C-library contract, described in [The installed C contract](#the-installed-c-contract) |
| `zig build test` | builds and runs `tests.zig` **in Debug and in ReleaseSafe itself** — one command, both modes |
| `zig build smoke` | runs `smoke.zig`, which asserts Unicode's published answer for a conformance row and exits non-zero on any mismatch |
| `zig build check` | compile-only: full C core, facade, test root and example for all six cross targets, with every public facade method instantiated |
| `zig build check -Dtarget=<triple>` | the same check for one target |
| `cross-test` | compiles **and runs** this package's `test` step over the full published 53-platform Zig 0.16.0 matrix, one `zig build test -Dtarget=…` per target. Settings come from `cross-test.profile.sh`; see [The full 53-platform matrix](#the-full-53-platform-matrix-cross-test) |
| `zig build -fsys=sheenbidi` | links an installed SheenBidi instead of building one |
| `cd consumer && zig build run` | the same library, consumed by a package that did not write it |

`-Doptimize` selects the mode of the default graph, of the example and of
`check`. It does **not** narrow `test`, which always runs both Debug and
ReleaseSafe — so running `test` twice with different `-Doptimize` values
executes the same two binaries again and proves nothing extra.

Add `-j8 --summary all`, and `--cache-dir <dir>`, as your workspace does.

The six cross-target checks, one command each, no target skipped:

```
zig build check -Dtarget=x86_64-linux-gnu  -j8 --summary all --cache-dir /home/tmp/gertullj/foundation-libs-cache/sheenbidi/x86_64-linux-gnu
zig build check -Dtarget=aarch64-linux-gnu -j8 --summary all --cache-dir /home/tmp/gertullj/foundation-libs-cache/sheenbidi/aarch64-linux-gnu
zig build check -Dtarget=aarch64-macos-none -j8 --summary all --cache-dir /home/tmp/gertullj/foundation-libs-cache/sheenbidi/aarch64-macos-none
zig build check -Dtarget=x86_64-windows-gnu -j8 --summary all --cache-dir /home/tmp/gertullj/foundation-libs-cache/sheenbidi/x86_64-windows-gnu
zig build check -Dtarget=riscv64-linux-gnu -j8 --summary all --cache-dir /home/tmp/gertullj/foundation-libs-cache/sheenbidi/riscv64-linux-gnu
zig build check -Dtarget=wasm32-wasi         -j8 --summary all --cache-dir /home/tmp/gertullj/foundation-libs-cache/sheenbidi/wasm32-wasi
```

`zig build check` with no `-Dtarget` walks all six in one graph. A cross check
compiles and links; it runs nothing, so a green one is compile evidence and
nothing more.

All six have been run, one attempt each with nothing skipped: each is green at
`Build Summary: 6/6 steps succeeded`, and the receipts are in
[Verification status](#verification-status).

## Using it

In your `build.zig.zon`:

```zig
.dependencies = .{
    .sheenbidi = .{ .path = "../sheenbidi" },
},
```

In your `build.zig`:

```zig
const dep = b.dependency("sheenbidi", .{ .target = target, .optimize = optimize });
exe_mod.addImport("sheenbidi", dep.module("sheenbidi"));
```

The library module carries its own C artifact, so a dependent does not have to
name `libSheenBidi.a`, an include path or `-lSheenBidi` itself. A dependent that
wants the C API still gets the headers: installing the archive also puts
`zig-out/include/SheenBidi/` on the include search path of anything that links
it. The consumer executable needs `link_libc = true` because SheenBidi allocates
with `malloc` and reads through the buffer it is handed.

Then:

```zig
const std = @import("std");
const sheenbidi = @import("sheenbidi");

// "car means " + three Hebrew letters + ".".
const text = "car means \u{05D0}\u{05D1}\u{05D2}.";
const source = sheenbidi.Source.fromUtf8(text);   // borrowed, never copied

var algorithm = try sheenbidi.Algorithm.create(source);
defer algorithm.deinit();

var paragraph = try algorithm.createParagraph(0, source.codeUnits(), .auto_ltr);
defer paragraph.deinit();

var line = try paragraph.createLine(paragraph.offset(), paragraph.length());
defer line.deinit();

for (line.runs()) |run| { /* one run of code units at one level */ }

const order = try line.visualOrder(std.heap.page_allocator);
defer std.heap.page_allocator.free(order);
```

`smoke.zig` and `consumer/src/main.zig` are both this, in working form, on two
published conformance rows — see [Examples](#examples).

## The API

Everything the facade exposes is below. The whole stable C surface stays
reachable through `pub const c`, the translated aggregate header, for anything
this facade does not name (including upstream's allocator protocol and the raw
code point decoders).

### Types and free functions

| Name | What it is |
|---|---|
| `Level`, `BidiType`, `Script`, `GeneralCategory`, `Codepoint`, `Run`, `CodeUnitIndex` | the upstream typedefs, unchanged. `CodeUnitIndex` is `SBUInteger`: an unsigned integer as wide as a pointer, and **every index, offset and length in this API is in code units** |
| `versionString() [:0]const u8` | `SBVersionGetString()` — the version of the linked C, `3.0.0` |
| `level_invalid` `0xFF`, `level_max` `125`, `level_default_ltr` `0xFE`, `level_default_rtl` `0xFD` | `Headers/SheenBidi/SBBase.h:143-158`. They are `#define`s, so translate-c does not publish them as values and they are transcribed here |
| `codepoint_invalid` `0xFFFFFFFF`, `codepoint_faulty` `0xFFFD`, `codepoint_max` `0x10FFFF` | `Headers/SheenBidi/SBCodepoint.h:35-49` |
| `bidi_type_*` (24 constants, `nil` `l` `r` `al` `bn` `nsm` `an` `en` `et` `es` `cs` `ws` `s` `b` `on` `lri` `rli` `fsi` `pdi` `lre` `rle` `lro` `rlo` `pdf`) | the 24 members of the `SBBidiType.h` enum, `SBBidiTypeNil` through `SBBidiTypePDF`, one `pub const` each at `zig/root.zig:198-221`, read out of the translated constants |
| `bidiTypeIsStrong` / `IsWeak` / `IsNeutral` / `IsFormat` | the four `SBBidiTypeIs*` families, transcribed from the macros with the same wrapping arithmetic |
| `generalCategoryIsLetter` / `IsMark` / `IsNumber` / `IsPunctuation` / `IsSymbol` / `IsSeparator` / `IsOther` | the `SBGeneralCategoryIs*` families |
| `codepointGeneralCategory`, `codepointBidiType`, `codepointMirror`, `codepointScript` | the four `SBCodepointGet*` lookups; `codepointMirror` returns `0` when the code point is not mirrored |
| `scriptUnicodeTag` | `SBScriptGetUnicodeTag` — the four-letter script tag as a big-endian `u32`, or `0` |
| `codepointIsSurrogate`, `codepointIsValid` | `SBCodepointIs*` |
| `codepointAt(source, index)`, `codepointBefore(source, index)` | `SBCodepointSequenceGetCodepointAt` / `...Before`, with the bounds check hoisted out of the C. Both return the code point and the next/start index; an out-of-range index yields `codepoint_invalid` and leaves the index where it was |

### Errors

Upstream has no error channel: it returns `NULL`. This facade checks the
arguments first, so the `NULL` that is left is upstream's allocation failure and
nothing else, and the taxonomy is cut at what this package actually checked:

| Error | Condition |
|---|---|
| `EmptySource` | the source has no code units. `SBCodepointSequenceIsValid` requires `stringLength > 0`, so `SBAlgorithmCreate` returns `NULL` |
| `RangeOutOfBounds` | the requested code-unit range does not fit inside the buffer it names. Upstream would clamp it instead (`SBUIntegerNormalizeRange`) |
| `EmptyRange` | the range is inside the buffer but covers no code units, which upstream reports as a `NULL` paragraph or line |
| `InvalidBaseLevel` | an explicit base level above `level_max` |
| `OutOfMemory` | SheenBidi could not allocate one of its objects |

### `Source` and the three encodings

| | |
|---|---|
| `Source.fromUtf8([]const u8)` / `fromUtf16([]const u16)` / `fromUtf32([]const u32)` | borrow a buffer in one of the three encodings `SBCodepointSequence` understands, native endianness for UTF-16 and UTF-32 |
| `Source.codeUnits() CodeUnitIndex` | the length **in code units** |
| `Source.byteLength() usize` | the same buffer in bytes |

The slices are borrowed and never copied. **Every offset, length and run in
SheenBidi counts code units, not code points**, so the same text has three
different index spaces: `"a\u{1F600}\u{05D0}"` is 7 code units in UTF-8
(`1 + 4 + 2`), 4 in UTF-16 (`1 + 2 + 1`) and 3 in UTF-32, and the resolved
levels are the same in all three. `tests.zig:488-490` pins those three counts
and `tests.zig:492-494` their byte lengths, 7, 8 and 12. A multi-byte code
point is followed by `BN` entries for the rest of its code units wherever a
per-code-unit table is exposed.

### `Algorithm`

| Operation | What it does |
|---|---|
| `Algorithm.create(source)` | an algorithm over one borrowed source. `EmptySource` for an empty one |
| `retain()` / `deinit()` | the upstream reference count. `retain` returns a second handle to the same object |
| `bidiTypes() []const BidiType` | the bidirectional type of every code unit, a view into the algorithm's own storage, one entry per code unit |
| `paragraphBoundary(offset, suggested)` | rule P1: where the first paragraph in `[offset, offset + suggested)` ends, and how many code units its separator occupied (`2` for a CRLF pair, `1` for a lone CR or LF, `0` when the range ran out). A range that fits is accepted even when empty, which reports no paragraph and no separator |
| `createParagraph(offset, suggested, base)` | the first paragraph in that range. **The paragraph retains the algorithm**, so it stays usable after this handle is deinitialised |

### `Paragraph`

| Operation | What it does |
|---|---|
| `offset()`, `length()` | the paragraph's extent in source code units, separator included |
| `baseLevel()` | the resolved paragraph embedding level. For an automatic base this is the level P2 and P3 arrived at, not the sentinel that was passed in |
| `levels() []const Level` | the resolved level of every code unit, in source order, as a view into the paragraph's own storage. Code units rule X9 removes are present and carry the paragraph level, which is what rule L1 does to them |
| `retain()` / `deinit()` | the upstream reference count |
| `createLine(line_offset, line_length)` | one line of the paragraph. **The line does not retain the paragraph**: the paragraph must outlive every line made from it |

### `Line` and the order of runs

| Operation | What it does |
|---|---|
| `offset()`, `length()`, `runCount()` | the line's extent and its number of runs |
| `runs() []const Run` | the line's runs **in visual order — left to right, the order they are drawn** |
| `retain()` / `deinit()` | the upstream reference count |
| `visualOrder(allocator) ![]CodeUnitIndex` | the code units of the line in the order they are drawn, as an explicit permutation of source indices. The caller owns the allocation; it has exactly `line.length()` entries |

`Line.runs()` returns runs that upstream has already permuted: `ReorderRuns`
(`Source/API/SBLine.c:234`) applies rule L2 to the run array as the line is
built, reversing contiguous runs at each level from the highest down to level 1.
It permutes the array and nothing else — a run's `offset` and `length` still
name the same code units in the source — so a run at an **odd** level is drawn
from `offset + length - 1` down to `offset`, and a run at an even level is drawn
forwards. `visualOrder` applies exactly that and returns the permutation, which
is the form a renderer or a test usually wants.

### `ScriptLocator` and `MirrorLocator`

| Operation | `ScriptLocator` | `MirrorLocator` |
|---|---|---|
| `create()` | a locator with nothing loaded | a locator with nothing loaded |
| `load(source)` | loads a source and rewinds. Loading is a borrow: the code units must stay alive and unmodified until the locator is deinitialised or loaded again. An empty source is accepted here, unlike `Algorithm.create` | — |
| `loadLine(line)` | — | loads a line and rewinds. The buffer is taken from the line itself rather than from a second argument, because upstream silently ignores a load whose buffer is not pointer-identical to the one the line was built from (`Source/API/SBMirrorLocator.c:56`), and an ignored load looks exactly like a line with no mirrors. The locator **retains** the line |
| `moveNext() bool` | advances to the next run, `false` once the source is exhausted. The locator rewinds itself at the end | advances to the next mirror, `false` once the line is exhausted. The locator rewinds itself at the end |
| `run()` | the current `ScriptRun` — offset, length, script | — |
| `mirror()` | — | the current `Mirror` — index, code point, mirrored code point. Only runs at an odd level are considered, because a mirror is applied where the character is drawn right to left (`Source/API/SBMirrorLocator.c:78`) |
| `reset()` | back to the first run | back to the first mirror |
| `retain()` / `deinit()` | the upstream reference count | the upstream reference count |

A script run is not simply the set of code points sharing a `Script` property
value: punctuation that pairs with mirrored punctuation inherits the script of
the text it encloses.

### Lifetimes, in one place

Upstream never copies the text it works on. `SBAlgorithmCreate` stores the
`SBCodepointSequence` — a pointer and a length — and reads through that pointer
long after the call that created it. Upstream states the rule at
`Headers/SheenBidi/SBAlgorithm.h:30`: "The source string inside the code point
sequence should not be freed until the algorithm object is in use."

So:

* **The code units are borrowed.** A `Source` is that rule made a type:
  `Algorithm`, `Paragraph` and `Line` each store a copy of the `Source` record,
  not of the text. The buffer must stay alive and unmodified until the last
  object derived from it is deinitialised. `ScriptLocator.load` and
  `MirrorLocator.loadLine` borrow on the same terms.
* **A `Paragraph` outlives its `Algorithm`** — `SBAlgorithmCreateParagraph`
  retains it (`Source/API/SBParagraph.c`, `CreateParagraph`).
* **A `Line` must not outlive its `Paragraph`** — `SBParagraphCreateLine`
  (`Source/API/SBParagraph.c:716`) validates the range and hands it to
  `SBLineCreate`, and neither retains the paragraph: the only `ObjectRetain` in
  `Source/API/SBLine.c` is `SBLineRetain` on the line itself (`:313`).
* **A `MirrorLocator` outlives the handle you gave it** — `SBMirrorLocatorLoadLine`
  retains the line (`Source/API/SBMirrorLocator.c:57`).
* **One allocator.** `deinit` hands the object back to the upstream release
  function, which frees it at refcount zero. There is no second allocator in the
  facade. `SBAllocatorSetDefault` and friends stay reachable through `c` for a
  caller that wants to move SheenBidi's allocations into a Zig allocator, but the
  facade does not expose them: a process-wide default allocator has no owner
  here, and a leak oracle for one would have to live outside the test framework.
* **The one allocation the facade makes** is `Line.visualOrder`, which is
  explicitly the caller's.

### Bounds

The C entry points take unsigned offsets and lengths and normalise them against
the source length (`SBUIntegerNormalizeRange`, `Source/API/SBBase.c:32`), which
**clamps** an out-of-range request instead of reporting it, and computes
`offset + length` first — an expression that wraps for a large length. This
package checks both itself, before the call, with subtraction
(`length > total - offset`), which cannot wrap, and an out-of-range request is an
error rather than a silent clamp. The checks are ordinary comparisons, not
`std.debug.assert`, so they are live in ReleaseFast as well as in Debug and
ReleaseSafe.

### Base levels, and the 124/125 boundary

`BaseLevel` is a tagged union, not a bare `SBLevel`, because upstream treats the
sentinels very differently from a real level:

| Value | Meaning |
|---|---|
| `.auto_ltr` | rules P2 and P3 with a left-to-right fallback (`SBLevelDefaultLTR`) |
| `.auto_rtl` | rules P2 and P3 with a right-to-left fallback (`SBLevelDefaultRTL`) |
| `.{ .explicit = 0 ... 125 }` | the level the paragraph is resolved against, used verbatim — except for `125`, see below |

`DetermineParagraphLevel` (`Source/API/SBParagraph.c:255-260`) dispatches on
`baseLevel >= SBLevelMax`, so:

* an explicit level is used **verbatim** for `0` through `124`;
* **125 is the boundary**: `level_max` is inside the accepted range of the type,
  but upstream reads it as "not explicit" and resolves it through P2 and P3. A
  right-to-left text at `125` therefore comes back as level `1`, and a text with
  no strong character at `125` comes back as `0`;
* an explicit level above `125` is `Error.InvalidBaseLevel` — there is nothing
  left to hand upstream;
* a first-strong LTR string under `.auto_ltr` resolves to level **0**, which is
  the level P2 and P3 produce, not a sentinel.

`tests.zig` pins all of this, including a right-to-left text at explicit level
`124`, which is then raised to `125` for the Hebrew letter by rule I1 ("for all
characters with an even (left-to-right) embedding level, those of type R go up
one level", `Source/UBA/IsolatingRun.c:443`).

### The experimental text API

Upstream's text-editing API (`SBText`, `SBTextConfig`, `SBTextIterators`) is
compiled out: `Headers/SheenBidi/SBConfig.h:39` leaves
`SB_CONFIG_EXPERIMENTAL_TEXT_API` commented out,
`Headers/SheenBidi/SBBase.h:44-48` keys `SB_TEXT_API_SUPPORTED` off that macro,
and this build does not define it. The symbols do not exist in the archive, so
nothing in this package stubs them.

## Build modes

* **Default (bundled).** Compiles `Source/SheenBidi.c` with
  `-std=c90 -DSB_CONFIG_UNITY` from this repository. That one unity file
  `#include`s all 32 checked-in `.c` units, so the archive is the whole library:
  the 15 API units, 4 core units, 4 generated UCD tables, the script stack, 2
  text-support units (compiled to nothing, see above) and 6 UBA run units. It is
  upstream's own default configuration, and the single entry is deliberate — a
  glob would let a unit be added or dropped from the archive without a decision.
  Atomics and thread-local storage are left to the source's own feature
  detection, so a threaded target gets real atomics rather than a silent
  non-atomic fallback.
* **`-fsys=sheenbidi`.** `b.systemIntegrationOption` puts the library on the
  build graph's system-library map, which the build runner fills from `-fsys=`
  and `-fno-sys=`, never from the `-D` option map — so the switch is spelled
  that way, and there is no `-Dsystem=sheenbidi` that would do anything. In this
  mode no archive of ours is produced, nothing is installed, and both the
  translation and the facade bind to the system library and the system header:
  the bundled include path is **not** added, so `<SheenBidi/SheenBidi.h>` is the
  header the installed library was installed with, and `pkg-config` is asked for
  the name (`-lSheenBidi`, capitalised, as upstream installs it) and the flags.
  It is off by default because a distro package of SheenBidi is very unlikely
  to be the 3.0.0 this manifest pins, and translating a header from one release
  against a library from another is the silent-wrong-answer failure this package
  exists to avoid. `check` in this mode stays on the requested target and says
  so, rather than reporting a six-target matrix it never looked at.
  **This mode has not been gated in this workspace and no run of it is claimed.**

## The installed C contract

`zig build --prefix <dir>` writes two things and nothing else:

```
<dir>/lib/libSheenBidi.a       the static archive — one unity translation unit
<dir>/include/SheenBidi/*.h    upstream's 23 public headers, unedited
```

The headers are installed *into* the include path rather than beside the
archive, so `-I <dir>/include` is the whole search path a C caller needs, and
`#include <SheenBidi/SheenBidi.h>` — the aggregate header, spelled exactly as
`zig/translate.h` spells it — is the one thing such a program has to include.
No configuration macro is passed to the consumer and none is needed: the only
`SB_CONFIG_*` the core is compiled with is `SB_CONFIG_UNITY`, which turns
`SB_INTERNAL` into `static` for the library build and says nothing about a
consumer's view of the headers, and `Headers/SheenBidi/SBConfig.h` ships every
macro commented out.

That contract is observed, not merely described. The driver installed to a
prefix on a second host — `zig build --prefix <dir>`, green, with the core
**compiled** rather than reused, `compile lib SheenBidi Debug native success 4s`
(`…-sheenbidi-installed-artifact-gruenau8-175.log`) — and then compiled and ran
a C program against nothing but the two installed paths:

```
zig cc -I <dir>/include <dir>/lib/libSheenBidi.a c_surface_gate.c -o c_surface_gate
./c_surface_gate
```

`…-sheenbidi-installed-C-surface-180.log` is that run: exit 0, 58 `ok` lines and
no `FAIL`, closing on `the installed C surface compiled, linked and ran`. Every
other gate in this package reaches SheenBidi through the Zig facade; this one
reaches it as a C library, which is what the fork is first. None of the facade
gates would notice a facade that was correct while the C surface a C caller
compiles against was not.

What it pins, on `"abc "` followed by U+05D0 HEBREW LETTER ALEF and U+05D1
HEBREW LETTER BET — six code points in eight UTF-8 code units:

* `SBCodepointSequenceGetCodepointAt` walks the Hebrew pair: code unit 4 is
  U+05D0 and leaves the index at 6, code unit 6 is U+05D1 and leaves it at 8,
  and code unit 8 — the end of the buffer — yields `SBCodepointInvalid` with
  the index **left where it was** rather than advanced.
* An explicit base level of `0` and the header's own `SBLevelDefaultLTR` request
  both resolve to a paragraph base level of `0`, and the same eight levels come
  out either way: `0` for the first four code units, `1` for the last four.
* `SBParagraphCreateLine` yields one line of two visual runs: offset `0`,
  length `4`, level `0`; then offset `4`, length `4`, level `1`.
* The ownership graph is checked rather than copied: `SBLineRetain` returns the
  same object, the line is still readable after the handle that created it is
  released, and `SBParagraphRetain` keeps a paragraph usable after its
  algorithm handle is gone.

The expected values are derived from the rules of UAX #9 in that program's own
comments rather than read back out of this build, so a wrong answer and a wrong
expectation fail it differently. It is generated inside
`.github/workflows/verify.yml`, whose `native` job runs it as the step
"installed C headers compile, link and run" — after `zig build` and ahead of
`test`, so a break in the C contract fails CI before the tests do.

## Examples

Two programs, both on published conformance rows rather than invented strings,
both of which exit non-zero if any asserted value disagrees:

* `smoke.zig` replays `BidiCharacterTest.txt` line 44 — the worked example from
  UAX #9 — as an explicit left-to-right paragraph. It asserts the paragraph
  level, the four runs in visual order
  (`[0..2] level 1`, `[2..3] level 0`, `[3..5] level 1`, `[5..14] level 0`) and
  the 14-entry visual order, then prints them. The version line is printed, not
  asserted: which release the binary is linked against belongs to the provenance
  gate.
* `consumer/src/main.zig` replays line 45 — the same text under an explicit
  right-to-left paragraph — and additionally walks the mirrors, because that is
  what a layout engine does with this library: take a paragraph, ask for its
  base level, ask for the runs, then ask which mirrored characters are inside a
  right-to-left run. It expects four mirrors, at indices 9, 11, 2 and 5, and it
  fails if a fifth appears. Its expected values are written out as literals
  rather than read from the fixture, because a consumer of a published package
  does not have the package's test data — which is what makes it an independent
  check of the run order rather than a restatement of it.

## Testing approach

The primary fixture is Unicode's own, and it is an independent known answer: the
expectations were produced by the Unicode Consortium, not by this fork and not
by SheenBidi.

| Test | Fixture | What it replays |
|---|---|---|
| `conformance: every row of BidiCharacterTest.txt` | `Tools/Unicode/BidiCharacterTest.txt`, 6 880 771 bytes | **all 91 707 data rows**, each as real code points in UTF-32: the resolved paragraph level, one resolved level per code point with `x` where rule X9 removed it, and the visual order |
| `conformance: every row and direction of BidiTest.txt` | `Tools/Unicode/BidiTest.txt`, 7 959 988 bytes | **all 490 846 data rows** across the paragraph directions each row's bitset selects — **770 241 cases** in total |
| `conformance: BidiTest representatives match DerivedBidiClass.txt` | `Tools/Unicode/DerivedBidiClass.txt` | every `Bidi_Class` representative the second test replays, checked against Unicode's own derived property file, plus ten anchors that do not depend on the representative table at all |

`BidiTest.txt` states its cases as `Bidi_Class` property values rather than as
code points and says a conforming implementation may "randomly pick characters
from those with the same Bidi_Class values". The harness turns each value into
one fixed representative code point and checks every one of them against
`DerivedBidiClass.txt`; without that check a wrong representative would quietly
replay a different property sequence from the one the fixture describes.

A pass states the whole file: both conformance tests count the rows they
replayed and compare the count with the constant above, so a green run is a
full-file replay and not an error-free prefix.

The remaining 16 tests are boundary cases the fixtures cannot reach: rule P1
across a CRLF pair, rule L1 on a trailing whitespace run and on a segment
separator, one text in all three encodings, rejected ranges, the base-level
boundary at 124 and 125, per-code-unit bidi types, the codepoint and script and
mirror lookups, code point decoding in each encoding, the mirror locator's
odd-level rule and its retention of the line, script runs over mixed text, the
paragraph-outlives-algorithm ownership rule and the `retain`/`deinit`
transitions. Three of them quote a named fixture row by line number — 44, 45 and
256 — because each is the smallest published example of one behaviour and a
failure that points at one named row is worth more than one that points at a
row number in a seven-megabyte file.

A same-code round trip is not what any of this rests on.

## Verification status

This table is the authoritative gate matrix for this package. Every receipt
below was produced by the driver, and nothing outside the table is claimed. Only
the three rows that say **(materialised copy)** ran inside a package fetched
from this directory; every other row ran against this working tree.
[`FORK-NOTES.md`](FORK-NOTES.md) carries the same status from the point of view
of each decision and links here rather than repeating the output.

| Gate | Command | Observed | Receipt |
|---|---|---|---|
| integrity | `sha256sum -c UPSTREAM.sha256` | green, exit 0 — 218 records, every line `<path>: OK`, nothing failed | `…-sheenbidi-immutable-source-integrity-120.log` |
| install | `zig build` | green, `Build Summary: 6/6 steps succeeded`; installs the archive and the headers and compiles the example | `…-sheenbidi-final-install-106.log` |
| install to a prefix, second host | `zig build --prefix <dir>` | green, `Build Summary: 6/6 steps succeeded`, with the core **compiled** rather than reused: `compile lib SheenBidi Debug native success 4s MaxRSS:115M` | `…-sheenbidi-installed-artifact-gruenau8-175.log` |
| installed C surface | `zig cc -I <dir>/include <dir>/lib/libSheenBidi.a c_surface_gate.c -o …`, then run the result | green, exit 0, 58 `ok` lines and no `FAIL` — see [The installed C contract](#the-installed-c-contract) | `…-sheenbidi-installed-C-surface-180.log` |
| test | `zig build test` — **one command, Debug and ReleaseSafe** | green, `Build Summary: 11/11 steps succeeded; 38/38 tests passed` | `…-sheenbidi-final-debug-96.log` and `…-sheenbidi-final-releasesafe-103.log` |
| smoke | `zig build smoke` | green, `Build Summary: 6/6 steps succeeded`, `run exe sheenbidi-smoke success 4ms` | `…-sheenbidi-final-smoke-91.log` |
| consumer | `zig build run --summary all` in `consumer/` | green, exit 0, 6/6 steps; the buffered writer is explicitly flushed and prints the 14-codepoint visual order and four mirrors before `all published values for row 45 reproduced` | `…-sheenbidi-consumer-stdout-flush-live-438.log` |
| native round 2026-10-02: **test + smoke + install**, one Debug invocation | `zig build test smoke install -Doptimize=Debug -j8 --summary all` | green, exit 0 in 7.348 s, `Build Summary: 19/19 steps succeeded; 38/38 tests passed` — 19 in Debug plus the same 19 in ReleaseSafe, and `smoke` and `install` in the same graph | `…-sheenbidi-native-Debug.log` (`local://foundation-cross-test-stable-sheenbidi-native-Debug.log`) |
| native round 2026-10-02: **smoke**, ReleaseSafe | `zig build smoke -Doptimize=ReleaseSafe -j8 --summary all` | green, exit 0 in 0.278 s, `Build Summary: 6/6 steps succeeded`, and **no test count at all** — this row runs `smoke` only. It is not a second 38/38 and not a second 19 | `…-sheenbidi-native-ReleaseSafe.log` (`local://foundation-cross-test-stable-sheenbidi-native-ReleaseSafe.log`) |
| native round 2026-10-02: **consumer** | `zig build run -j8 --summary all` in `consumer/` | green, exit 0 in 0.173 s, 6/6 steps | `…-sheenbidi-native-consumer.log` (`local://foundation-cross-test-stable-sheenbidi-native-consumer.log`) |
| cross check, six targets | `zig build check -Dtarget=<triple>`, one command each, none skipped | green, `Build Summary: 6/6 steps succeeded` for each: `x86_64-linux-gnu` `-132`, `aarch64-linux-gnu` `-136`, `aarch64-macos-none` `-139`, `x86_64-windows-gnu` `-142`, `riscv64-linux-gnu` `-145`, `wasm32-wasi` `-148` | `…-sheenbidi-matrix-<target>-<n>.log` |
| six-target baseline re-run, 2026-10-02 | `zig build check -Dtarget=<triple> -Doptimize=Debug -j8 --summary all`, one command each, none skipped | green, exit 0 and `Build Summary: 6/6 steps succeeded` for all six — `x86_64-linux-gnu` 2.835 s, `aarch64-linux-gnu` 5.310 s, `aarch64-macos-none` 4.411 s, `x86_64-windows-gnu` 5.011 s, `riscv64-linux-gnu` 4.481 s, `wasm32-wasi` 3.743 s. Still compile-only: no cell ran a binary | `…-baseline-sheenbidi-<target>.log` |
| **full 53-platform `cross-test` matrix**, final run 2026-10-02 | `cross-test --jobs 2 --build-jobs 2 --build-timeout 3600` from this directory, with `cross-test.profile.sh` sourced and no timeout override | green, **exit 0**: **20 pass, 33 build_only, 0 fail** over all 53 published targets. Every passing cell is `Build Summary: 11/11 steps succeeded; 38/38 tests passed`; every `build_only` cell is `Build Summary: 9/11 steps succeeded (2 skipped)` | `local://foundation-cross-test-final-sheenbidi-<target>.log`, one per target |
| pinned native upstream bytes | `git diff --exit-code cfe430e7… -- Headers Source Tests Tools LICENSE CMakeLists.txt Makefile meson.build meson_options.txt` | green, exit 0, **empty output** — the C tree, the fixtures, the tests, upstream's build systems and the licence are the pinned commit's bytes. A direct diff of this working tree against the pinned commit: **not** a replay of `git archive`, and **not** a CI run | `…-sheenbidi-pinned-native-pristine-diff-265.log` |
| `zig fetch` (packaged copy) **(materialised copy)** | `zig fetch <this package directory> --global-cache-dir <scratch>/packages`, run from an external approved scratch build root | green, exit 0 at receipt 440, after the consumer flush: `sheenbidi-3.0.0-PIPqq_cnPAHHpPnjFuv7nc5-dgtiNxsmOpfmw-Q-ZnsO`. This is that observed snapshot's identity, not a hash for later documentation edits, and that snapshot predates `cross-test.profile.sh` — see [Not observed](#not-observed) | `…-sheenbidi-consumer-stdout-flush-filtered-fetch-440.log` |
| integrity, **inside the fetched package** **(materialised copy)** | `sha256sum -c UPSTREAM.sha256`, run in that materialised copy | green, exit 0 — the same 218 records, every line `<path>: OK`, nothing missing | `…-sheenbidi-stdout-closed-package-integrity-443.log` |
| consumer, **inside the fetched package** **(materialised copy)** | `zig build run --summary all --cache-dir <scratch> --global-cache-dir <zig cache>` in that copy's `consumer/` | green, exit 0, 6/6 steps; prints visual order `12 13 11 10 9 7 8 6 5 4 3 2 1 0`, four mirrors and the row-45 confirmation. The earlier empty-output receipt 338 remains history, superseded by the explicit flush | `…-sheenbidi-stdout-closed-package-consumer-444.log` |

**Why the `test` row names two receipts, and what `38/38` counts.** The `test`
step builds and runs `tests.zig` in Debug and in ReleaseSafe itself, so each
invocation carries `run test 19 pass (19 total)` twice, once per mode, under a
single `Build Summary: 11/11 steps succeeded; 38/38 tests passed`. There are two
receipts because the step was invoked twice; `-Doptimize` does not narrow it, so
the second invocation ran the same two binaries. **Neither receipt is a
single-mode count**: `38/38` is nineteen tests in Debug plus the same nineteen
in ReleaseSafe, and reading either receipt as "38 in Debug only", or as "38 in
ReleaseSafe only", is reading a number this build never produced.

**What the green `test` receipts establish.** All nineteen tests pass in both
modes, and that includes the two conformance replays in full: each counts the
rows it replayed and compares the count with a constant, so a pass is 91 707
character rows and 490 846 property rows / 770 241 cases rather than an
error-free prefix. It also includes `tests.zig:944` — the assertion whose
expected value was wrong, described in [`CHANGELOG.md`](CHANGELOG.md) entry 11.
Those receipts ran after that edit, so the correction is observed rather than
merely landed.

**Earlier empty-output receipts.** The original install, smoke and consumer
receipts recorded step success without printed example values; 338 was also
empty. They remain historical evidence, not a record of stdout. After the
consumer's explicit flush, working-tree receipt 438 and copied-package receipt
444 include the visual order, mirrors and final row-45 confirmation. Those
lines are now observed output, alongside the independently exercised installed
C surface described in [The installed C contract](#the-installed-c-contract).

**What the six cross checks are, and are not.** They are compile-and-link
evidence: `zig build check` builds the C core, the facade, the test root and the
example for the target and runs none of them. A green row for one of these six
targets says the package compiles and links there, not that the UCD replays pass
there. The six-target baseline re-run is the same shape: six green cells, no
cell running a binary. The replays *have* now run on some of these architectures,
but only under the full matrix below, which is a different gate with a different
receipt — `aarch64-linux-gnu` and `riscv64-linux-gnu` are compiled here and
executed there as `aarch64-linux` and `riscv64-linux`, while
`aarch64-macos-none`, `x86_64-windows-gnu` and `wasm32-wasi` have no runner in
any run of this package and remain compile-only everywhere.

**What the 2026-10-02 native round adds.** The Debug row is one
`zig build test smoke install` graph, so its `38/38` is the same nineteen in
Debug plus the same nineteen in ReleaseSafe that the two older `test` receipts
record — it is not a third copy of the count and the twenty matrix cells are not
nineteen more. The ReleaseSafe row runs `smoke` and reports no tests at all; it
exists to exercise the smoke program in the optimised mode, and reading it as a
19-test or 38-test run invents a number it never printed. All three rows ran on
the host that produced them, with a per-row cache directory and prefix, and the
consumer row ran against the tree those rows installed.

**What the materialised-copy rows add, and what they do not.** The `zig
fetch` row ran from an external approved scratch build root over this package
directory, so what it produced is a filtered copy of exactly what
`build.zig.zon`'s `.paths` lists — not a Git clone, and not a build of this
working tree. The two rows after it ran **inside that copy**: the 218-record
check found every file the record names present and matching, which is the first
run here that binds the record to `.paths` rather than to this tree, and
`consumer/` built the fetched library and exited 0 in a package that did not
write this one. What none of the three says anything about is publication or
registry resolution: the fetch source was a local directory, so no remote URL,
no registry index and no published `.hash` was exercised, and no publication is
authorized. **That copy predates `cross-test.profile.sh`**, so it is evidence
about the package as it stood before entry 18 of
[`CHANGELOG.md`](CHANGELOG.md) and is not evidence that the profile travels in a
fetched package. The pinned-native diff row is a separate observation about
**this** working tree, and nothing in the materialised copy restates it.

### The full 53-platform matrix (`cross-test`)

`zig build check` answers six compile-only questions. `cross-test` answers the
published 53-platform one, and it answers it by running this package's real
test step rather than by compiling it: with no artifact hooks it runs
`zig build test -Dtarget=TARGET` once per target (`cross-test:383-385`), over
the Zig 0.16.0 Tier 1/2 support table (`zig-targets.sh:36-67`). The matrix, the
native/QEMU/Wine/Wasmtime detection and the decision to skip a foreign run are
the harness's; this package contributes the `test` graph and a
`cross-test.profile.sh` of four ordinary Bash variable definitions.

The `test` step is what makes that meaningful here: it attaches a **run**
artifact for every mode it builds (`build.zig:329-340`), so a cell with a runner
executes all nineteen tests and a cell without one still compiles them. When the
harness declines to run a foreign binary it replaces that run step's action with
a skip and leaves its compile dependencies in place (`run_policy.zig:55-57`,
`:103-105`), so the cell is `build_only` — compile evidence, never a pass.

`cross-test.profile.sh` sets `CROSS_BUILD_STEP=test`, `CROSS_BUILD_JOBS=2`,
`CROSS_BUILD_TIMEOUT=3600` and `CROSS_TIMEOUT=1800`. It defines no hooks, no
matrix and no host path, every value is a default the command line overrides,
and `CROSS_LIBC_RUNTIMES` is deliberately left to the environment: it names
foreign libc loaders on the machine running the harness, not something this
package knows.

**How to read a count.** One cell that runs is `38/38 tests passed`, for the
same reason the native `test` row is: nineteen in Debug and the same nineteen in
ReleaseSafe, from one `zig build test`. It is never "38 in Debug". The nineteen
are unchanged — both UAX #9 replays, the representative check and the sixteen
boundary cases — and no cell is allowed to run a subset of them.

**Observed.** The final run of 2026-10-02 is `cross-test --jobs 2 --build-jobs
2 --build-timeout 3600` from this directory, with `cross-test.profile.sh`
sourced and no command-line override of the deadlines the profile sets; harness
run id `20261002-062101-65268-4429`, `--test-timeout 1800s` per cell. It
covered all 53 published targets and exited **0**: **20 pass, 33 build_only, 0
fail**, `status: partial` because a `build_only` cell is not a pass.

The twenty cells that ran — `x86_64-linux` natively and nineteen foreign
triples under the harness's own runner detection — are `x86_64-linux`,
`x86-linux`, `aarch64-linux`, `aarch64_be-linux`, `arm-linux`, `armeb-linux`,
`thumb-linux`, `thumbeb-linux`, `hexagon-linux`, `loongarch64-linux`,
`mips-linux`, `mipsel-linux`, `mips64-linux`, `mips64el-linux`, `powerpc-linux`,
`powerpc64-linux`, `powerpc64le-linux`, `riscv32-linux`, `riscv64-linux` and
`s390x-linux`. Every one of them is `Build Summary: 11/11 steps succeeded;
38/38 tests passed`: all nineteen tests in Debug and the same nineteen in
ReleaseSafe, and nothing dropped to reach it.

The thirty-three that did not run are `Build Summary: 9/11 steps succeeded (2
skipped)`, and the two skipped steps are the harness's own run steps, not a
subset of tests: 24 FreeBSD/NetBSD/OpenBSD cells, 4 Darwin cells
(`aarch64-macos`, `x86_64-macos`, `aarch64-maccatalyst`, `x86_64-maccatalyst`),
4 Windows cells (`x86-windows`, `x86_64-windows`, `aarch64-windows`,
`thumb-windows`) and `wasm32-wasi`. **No BSD, Darwin, Windows or WASI cell of
this package has ever executed anything.** They compile and link, which is what
`build_only` means, and no runner claim is made for any of them.

**Nothing was removed to get there.** The nineteen tests, both modes, the two
embedded fixtures (`Tools/Unicode/BidiTest.txt`, 7.6 MB, and
`Tools/Unicode/BidiCharacterTest.txt`, 6.6 MB) and the 218-record integrity list
are the same in this run as before it, and a passing cell still replays 490 846
property rows (770 241 cases) plus 91 707 character rows per mode. No test was
skipped, no mode dropped and no corpus file excluded to move the two cells the
first sweep timed out on; the twenty are twenty cells of the same published
53-target list, not a shorter one.

**The native assumption a cell could have broken, and what the run says.**
`Source/Core/ThreadLocalStorage.h:57-60` selects `__thread void *` for any
Clang target at the pinned C dialect, because `-std=c90` leaves
`__STDC_VERSION__` undefined and `Source/API/SBBase.h:58-66` therefore takes the
`USE_ATOMIC_BUILTINS` branch; `Source/API/SBAllocator.c:24` includes that header
unconditionally. A target whose C compiler has no thread-local storage would
fail to compile the unity unit there. All 53 published targets compiled it,
and the twenty that have a runner executed it, so the assumption held
everywhere this run could see. That is an observation bounded by this matrix
and this compiler, not a property of every target Zig can name; no native file
has been changed for it, and none needed to be.

### Earlier runs, and the failures they recorded

Kept because they are the record of what was wrong, not as current state.
Everything above supersedes them.

| Gate | Receipt | What it recorded |
|---|---|---|
| install | `…-sheenbidi-native-install-43.log` | green, 6/6 steps. Superseded by `-106` |
| smoke | `…-sheenbidi-first-smoke-proof-42.log` | green, 6/6 steps, `run exe sheenbidi-smoke success 5ms`. Superseded by `-91` |
| smoke | `…-sheenbidi-latest-smoke-83.log` | green, 6/6 steps. Superseded by `-91` |
| test (both modes) | `…-sheenbidi-corrected-debug-37.log`, `…-sheenbidi-corrected-releasesafe-44.log` | **red**: `18 pass, 1 fail (19 total)` in each mode, `Build Summary: 8/11 steps succeeded (2 failed); 36/38 tests passed (2 failed)`. One failure, the same one in both modes — `expected 1, found 0` at `tests.zig:944`. Both receipts name the same object hash, because `-Doptimize` does not narrow the step, so both invocations ran the same two binaries |
| consumer | `…-sheenbidi-corrected-consumer-45.log` | green, 6/6 steps, and the only receipt in the set that shows the C library being compiled rather than reused: `compile lib SheenBidi Debug native success 2s MaxRSS:122M` |
| test | `…-sheenbidi-initial-debug-13.log`, `…-sheenbidi-repaired-debug-21.log` | **red**: compile errors, `Build Summary: 6/11 steps succeeded (2 failed)`. These are the four fixes in [`CHANGELOG.md`](CHANGELOG.md) entries 7–9 and [`FORK-NOTES.md`](FORK-NOTES.md) L1–L3 |
| full 53-platform `cross-test` matrix, first sweep | `local://foundation-cross-test-matrix-sheenbidi-<target>.log`, run id `20261002-040254-42806-17091`, `cross-test --jobs 2 --build-jobs 4 --build-timeout 1800` | **exit 1**: 19 pass, 32 build_only, **2 fail**. `x86_64-linux` and `aarch64-freebsd` both hit `per_build_timeout` with build `exit 124` and `run: not_run`. Superseded by the final run above, in which both cells compile and `x86_64-linux` runs 38/38. That command line **overrode the profile's** `CROSS_BUILD_TIMEOUT=3600` and `CROSS_BUILD_JOBS=2` with 1800 and 4, and it also used a different cache directory, so the two sweeps differ in three settings at once and neither this table nor the receipts isolate which one ended the timeouts. Nothing in the package changed between them |

The failing assertion those red receipts name is fixed: `tests.zig:944` reads
`try std.testing.expectEqual(@as(sheenbidi.Level, 0), retained.baseLevel())`,
and the green receipts above ran after that edit. The red receipts stay red
because they describe the file as it stood when they were taken.

### Not observed

Three things are still unobserved, and no result is claimed for any of them.

| Item | State |
|---|---|
| replaying `git archive` against `9bdf0c279f…cac4a28` | **not run.** It needs a re-fetch of upstream, which this workspace does not have. The digest is the driver's, recorded at import time in [`UPSTREAM.md`](UPSTREAM.md). The 218-record `sha256sum -c` above establishes this tree against the record; it does not establish the tree against upstream |
| `zig build -fsys=sheenbidi` | **not run.** It needs an installed `libSheenBidi` at this manifest's pinned 3.0.0 with its own matching header, and none is available here |
| the package round **after** `cross-test.profile.sh` — filtered fetch, source/fetched integrity and fetched consumer | **Driver-owned closure proof.** The current result and package identity are in the workspace ledger's `cross_test_wave.materialized_packages.sheenbidi` and `local://foundation-cross-test-package-regression.json`. The historical rows above predate the profile. Final identities stay outside package-local documents, which contribute to those identities |

The installed C surface gate is **not** the system mode, and does not stand in
for it. That gate compiles and runs against the archive and the headers this
build had installed a moment earlier; no system SheenBidi was present, nothing
was asked of `pkg-config`, and no `-fsys=` switch was passed. What it observes
is that this build's own install produces a usable C package. What it cannot
say is anything about `-fsys=sheenbidi`, which remains ungated and remains
unclaimed — including at run time, not only at compile time.

Upstream's own C++ suite in `Tests/` is not compiled by this package's build; it
travels with it for provenance and for a re-sync diff.

## Integrity

```
sha256sum -c UPSTREAM.sha256
```

218 records covering every upstream file this package ships — the whole
`Headers/`, `Source/`, `Tools/` and `Tests/` trees, upstream's two build systems
and their two `.in` templates, `LICENSE` and `README.md` — and nothing else, so
the same command works in a clone and in an unpacked package. That includes the
Unicode fixtures the test root embeds and the Apache-2.0 text, not just the
sources the build compiles. See [`UPSTREAM.md`](UPSTREAM.md) for how the
digests were produced and what they do and do not prove.

Run, that check is green: exit 0, 218 records, every line `<path>: OK`
(`…-sheenbidi-immutable-source-integrity-120.log`). The workflow also schedules
it, at `.github/workflows/verify.yml:57-58`, ahead of `zig build` — that is read
out of the file, and **no CI run of this package has been executed here**, so no
hosted-runner result is claimed.

The record has also been checked where a dependent finds it: run **inside the
package `zig fetch` materialised from this directory**, it reported the same 218
records, every line `OK`, with nothing missing
(`…-sheenbidi-materialized-package-integrity-331.log`). So every file the record
names is one `build.zig.zon`'s `.paths` actually delivers — including the eleven
Unicode fixtures under `Tools/Unicode/` and the Apache-2.0 text — which is a
claim about the package and not only about this working tree. That fetch was of a
local directory: it says nothing about publication or about resolution from a
registry, neither of which has been tested. Both materialised-copy checks
predate `cross-test.profile.sh`, so neither is evidence about the profile; see
[Not observed](#not-observed).

## Licence

Upstream's library is `Apache-2.0`; the text ships verbatim as `LICENSE`, and
90 of the 98 files under `Headers/` and `Source/` carry the same notice. The
eight that carry none are the generated UCD tables in `Source/Data/`, which the
grant covers anyway because it covers the package rather than the file. The
eleven Unicode data files in `Tools/Unicode/` are **not** covered by it: they
are Unicode, Inc. data files under the terms their own headers name, they
travel unmodified with their notice intact, and this package neither restates
nor relicenses them. The fork-authored files have no stated licence; their status
is unassigned and no grant may be inferred from the upstream terms.
Attribution, the licence split, the files this fork adds or edits and the
patent-grant termination clause are in [`NOTICE.md`](NOTICE.md).
