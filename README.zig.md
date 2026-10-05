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

The compiler is also available from this package's own development
environment — `devenv shell`, or `direnv allow` through `.envrc` — which
supplies Zig 0.16.0 and pkg-config as tools and builds nothing when it opens.
See [Nix and devenv](#nix-and-devenv).

The core needs the C library headers `stddef.h`, `stdint.h`, `stdlib.h` and
`string.h` and nothing else, which is upstream's own dependency statement
(`README.upstream.md:71-72`; it was `README.md` before this fork gave that name
to its own README, and the bytes are identical).

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
| `zig build -Dlinkage=dynamic` | **added by this migration**, observed 2026-10-04. Selects the artifact: `static` (the default, and this package's policy unchanged) produces `libSheenBidi.a`, `dynamic` produces `libSheenBidi.so`. It selects the *delivery*, never the dispatch: the same C is compiled either way |
| `zig build -Druntime=true` | **added by this migration**, partly observed 2026-10-04. `c` becomes a generated dispatch and the facade is not linked against `libSheenBidi`; the artifact is still built and installed. Eight such gates exited 0 with `SHEENBIDI_PROVIDER` set to a separately built `libSheenBidi.so`, so the load path itself is exercised; the `bin/misuse` observations are not. `tests.zig` and `smoke.zig` take their provider from `SHEENBIDI_PROVIDER` or `--provider <path>` and stop, naming both, when neither is set — `build.zig` deliberately does not export it, because under `-Dlinkage=static` there is no provider path to name. See [Runtime loading](#runtime-loading-and-the-abi-it-needs) |
| `devenv shell`, or `direnv allow` | the canonical development environment: Zig 0.16.0 and pkg-config as tools, and namespaced `sheenbidi:*` tasks that run this package's own build. It builds nothing when it opens. See [Nix and devenv](#nix-and-devenv) |
| `devenv build outputs.static` / `outputs.shared` | the same `package.nix` the flake uses, from inside the shell |
| `nix build .#static` / `.#shared` / `.#default` | the Nix delivery of this same source tree. `default` is `static`; see [Nix](#nix-and-devenv) |
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

`dep.module("sheenbidi")` is the one supported import. The raw C surface is
reached as `sheenbidi.c` from inside that module, not as a second import: the
build registers the translated header under the graph name `c`
(`build.zig:441`) only because `zig/root.zig` binds it by that name, and it
holds the same declarations either way.

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
code point decoders). `c` is a supported escape hatch and carries upstream's
own contracts, not this facade's: a raw call that goes past a facade method has
none of the bounds checks below it. It is reached as `sheenbidi.c`. The build
also registers the translated header under the graph name `c`
(`build.zig:441`) because `zig/root.zig` binds it by that name; that is wiring,
not a second supported import, and it holds the same declarations.

### Types and free functions

| Name | What it is |
|---|---|
| `Level`, `BidiType`, `Script`, `GeneralCategory`, `Codepoint`, `Run`, `CodeUnitIndex` | the upstream typedefs, unchanged. `CodeUnitIndex` is `SBUInteger`: an unsigned integer as wide as a pointer, and **every index, offset and length in this API is in code units** |
| `versionString() [:0]const u8` | `SBVersionGetString()` — the version of the linked C, `3.0.0` |
| `level_invalid` `0xFF`, `level_max` `125`, `level_default_ltr` `0xFE`, `level_default_rtl` `0xFD` | `Headers/SheenBidi/SBBase.h:143-158`. Object-like `#define`s arrive as `pub const` through translate-c and are read from the translated module (`zig/root.zig`) |
| `codepoint_invalid` `0xFFFFFFFF`, `codepoint_faulty` `0xFFFD`, `codepoint_max` `0x10FFFF` | `Headers/SheenBidi/SBCodepoint.h:35-49`, read the same way |
| `bidi_type_*` (24 constants, `nil` `l` `r` `al` `bn` `nsm` `an` `en` `et` `es` `cs` `ws` `s` `b` `on` `lri` `rli` `fsi` `pdi` `lre` `rle` `lro` `rlo` `pdf`) | the 24 members of the `SBBidiType` enum, `Headers/SheenBidi/SBBidiType.h:28-55`, `SBBidiTypeNil` through `SBBidiTypePDF`, one `pub const` each, read out of the translated constants |
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
| `InvalidBaseLevel` | an explicit base level above `level_max` — `126` and up, which includes all three sentinels |
| `OutOfMemory` | SheenBidi could not allocate one of its objects. The memory is the C library's own, so a Zig leak oracle sees nothing on either side of it |

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
| `retain()` / `deinit()` | the upstream reference count. `retain` returns a **second handle the caller owns** and owes one `deinit`; a plain `var b = a;` copies the struct and increments nothing, so two `deinit` calls on the two copies release one count twice |
| `bidiTypes() []const BidiType` | the bidirectional type of every code unit, a view into the algorithm's own storage, one entry per code unit. It borrows the object: valid until every handle to it has been deinitialised |
| `paragraphBoundary(offset, suggested)` | rule P1: where the first paragraph in `[offset, offset + suggested)` ends, and how many code units its separator occupied (`2` for a CRLF pair, `1` for a lone CR or LF, `0` when the range ran out). A range that fits is accepted even when empty, which reports no paragraph and no separator |
| `createParagraph(offset, suggested, base)` | the first paragraph in that range. **The paragraph retains the algorithm** (`Source/API/SBParagraph.c:658`), so it stays usable after this handle is deinitialised — that retain covers the algorithm object, not the borrowed code units, which the paragraph goes on reading |

### `Paragraph`

| Operation | What it does |
|---|---|
| `offset()`, `length()` | the paragraph's extent in source code units, separator included |
| `baseLevel()` | the resolved paragraph embedding level. For an automatic base, and for `.{ .explicit = 125 }`, this is the level P2 and P3 arrived at, not the value that was passed in; for `.{ .explicit = n }` with `n <= 124` it is `n` unchanged |
| `levels() []const Level` | the resolved level of every code unit, in source order, as a view into the paragraph's own storage, valid until every handle to it has been deinitialised. Code units rule X9 removes are present and carry the paragraph level, which is what rule L1 does to them |
| `retain()` / `deinit()` | the upstream reference count, with the same second-handle and balanced-release rule as above |
| `createLine(line_offset, line_length)` | one line of the paragraph, with one reference the caller owns and owes one `deinit`. **The line does not retain the paragraph** (`Source/API/SBLine.c:279`): the paragraph must outlive every line made from it, including a line held alive by a `MirrorLocator` |

### `Line` and the order of runs

| Operation | What it does |
|---|---|
| `offset()`, `length()`, `runCount()` | the line's extent and its number of runs |
| `runs() []const Run` | the line's runs **in visual order — left to right, the order they are drawn**, as a view into the line's own storage. It borrows the line, so it dies when the last handle to that line is given back — including the one a loaded `MirrorLocator` holds |
| `retain()` / `deinit()` | the upstream reference count, with the same second-handle and balanced-release rule as above |
| `visualOrder(allocator) std.mem.Allocator.Error![]CodeUnitIndex` | the code units of the line in the order they are drawn, as an explicit permutation of **absolute source code unit indices**. This is the only allocation the facade makes: it has exactly `line.length()` entries, it comes from `allocator`, and the caller releases it with `allocator.free` on that same allocator. Its whole error channel is `error.OutOfMemory` — the allocation is the only step that can fail, and no partial result is produced when it does |

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
| `create()` | a locator with nothing loaded, with one reference the caller owns and owes one `deinit` | a locator with nothing loaded, with one reference the caller owns and owes one `deinit` |
| `load(source)` | loads a source and rewinds. Loading is a borrow: the code units must stay alive and unmodified until the locator is deinitialised or loaded again, and nothing is retained — loading a second source just replaces the sequence the walk reads. An empty source is accepted here, unlike `Algorithm.create` | — |
| `loadLine(line)` | — | loads a line and rewinds. The buffer is taken from the line itself rather than from a second argument, because upstream silently ignores a load whose buffer is not pointer-identical to the one the line was built from (`Source/API/SBMirrorLocator.c:56`), and an ignored load looks exactly like a line with no mirrors — there is no error for it. The locator **retains** the line (`Source/API/SBMirrorLocator.c:57`), so the line object outlives the handle given here; that reference is given back by the next `loadLine` (`:52`) or by `deinit`, which reaches `FinalizeMirrorLocator` (`:30`) |
| `moveNext() bool` | advances to the next run, `false` once the source is exhausted. The locator rewinds itself at the end | advances to the next mirror, `false` once the line is exhausted. The locator rewinds itself at the end |
| `run()` | the current `ScriptRun` — offset, length, script | — |
| `mirror()` | — | the current `Mirror` — absolute source code unit index, code point, mirrored code point. Only runs at an odd level are considered, because a mirror is applied where the character is drawn right to left (`Source/API/SBMirrorLocator.c:78`) |
| `reset()` | back to the first run | back to the first mirror |
| `retain()` / `deinit()` | the upstream reference count, with the same second-handle and balanced-release rule as above | the upstream reference count, with the same second-handle and balanced-release rule as above |

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

* **The code units are borrowed, through the last derived object.** A `Source`
  is that rule made a type and it is a plain value: `Algorithm`, `Paragraph`
  and `Line` each store a copy of the `Source` record, not of the text, and
  copying that record copies the borrow. The buffer must stay alive and
  unmodified until the last object derived from it is gone — the last
  `Algorithm`, `Paragraph`, `Line`, loaded `ScriptLocator` and loaded
  `MirrorLocator` among them, in whatever order they were made.
  `ScriptLocator.load` and `MirrorLocator.loadLine` borrow on the same terms,
  and a locator that is still loaded extends the obligation.
* **A `Paragraph` outlives its `Algorithm`** — `SBAlgorithmCreateParagraph`
  retains it (`Source/API/SBParagraph.c:658`). That retain is on the algorithm
  object only; the borrowed code units are still read by the paragraph.
* **A `Line` must not outlive its `Paragraph`** — `SBParagraphCreateLine`
  (`Source/API/SBParagraph.c:716`) validates the range and hands it to
  `SBLineCreate`, and neither retains the paragraph: `SBLineCreate` copies the
  code point sequence and nothing else (`Source/API/SBLine.c:279`), and the
  only `ObjectRetain` in that file is `SBLineRetain` on the line itself
  (`:313`).
* **A `MirrorLocator` outlives the handle you gave it** — `SBMirrorLocatorLoadLine`
  retains the line (`Source/API/SBMirrorLocator.c:57`). That is the line
  *object*: the locator inherits the paragraph rule above, and the code units
  remain the caller's obligation while it is loaded.
* **The count counts handles, not struct copies.** Every `create` and every
  `retain` produces one handle the caller owns and owes exactly one `deinit`.
  Assigning one value to another copies the struct and increments nothing, so
  `deinit` on both copies gives back two references against one count.
* **Native allocations are not Zig allocations.** `Algorithm`, `Paragraph`,
  `Line`, `ScriptLocator` and `MirrorLocator` are allocated and freed by
  SheenBidi, so `std.testing`'s leak oracle sees neither side of them.
* **The one allocation the facade makes** is `Line.visualOrder`, which is
  explicitly the caller's, from the allocator it passed and released by the
  caller through that same allocator.

#### Redirecting the native allocator

`SBAllocatorSetDefault` is reachable through `sheenbidi.c` and it is
**process-global**. `Source/API/SBAllocator.c:31` is a `static` atomic pointer
and the setter is a bare store into it (`:276-279`), so it reaches every thread
and every object in the process, including ones this facade never touched. This
facade does not wrap it and does not re-expose it under another name: a
process-wide default allocator has no owner here, and a leak oracle for one
would have to live outside the test framework.

What it controls, read out of the source:

* Every object block is allocated through `SBAllocatorAllocateBlock(NULL, …)`
  (`Source/Core/Memory.c:78`, `:95`), which resolves the **current** default at
  the moment of the call (`Source/API/SBAllocator.c:211-218`).
* Every free goes through `SBAllocatorDeallocateBlock(NULL, block)`
  (`Source/Core/Memory.c:144`), which resolves the current default **again**, at
  the moment of the release (`Source/API/SBAllocator.c:229-236`).
* No object and no memory block records the allocator it came from.

That last point is the retention rule, and it is a correctness requirement
rather than a preference: an object created while allocator `A` was the default
and released after the default became `B` is freed through `B`. **The default
in force at creation must still be in force at the last release, for every
object.** Arbitrary swaps are safe only while no object created under the
previous default is still live. Concretely, the safe authority to change it is:

* Install once, before the first SheenBidi object of the process is created, and
  keep it installed until the last object created under it has been released.
  Restoring the previous default, or `NULL`, is itself a change and obeys the
  same rule — this is **not** an allocator a caller may swap at will between
  calls.
* The setter does not retain. It is an `AtomicPointerStore` and nothing more,
  so the caller keeps the allocator object alive and valid for as long as it is
  the default. `SBAllocatorRetain` (`Source/API/SBAllocator.c:297`) and
  `SBAllocatorRelease` (`:302`) are the upstream reference count, and a process
  that installs the same allocator from more than one place has to count its own
  handles.
* The allocator object is itself allocated through the default in force when it
  was created and freed through the default in force when its own count reaches
  zero (`SBAllocatorCreate` calls `ObjectCreate`,
  `Source/API/SBAllocator.c:287`), so it obeys the same rule as every other
  object.

The protocol, as this implementation actually calls it: `allocateBlock` and
`deallocateBlock` are called unconditionally (`Source/API/SBAllocator.c:217`,
`:235`); `allocateScratch` and `resetScratch` are called only when non-`NULL`
(`:247-251`, `:264-268`), and a scratch request that comes back `NULL` falls
back to `allocateBlock` (`Source/Core/Memory.c:68-72`) rather than failing;
`reallocateBlock` is called unconditionally where a `List` grows
(`Source/Core/List.c:72`), which in this build is reached only from the
experimental text API that is not compiled. A member the implementation calls
unconditionally has to be non-`NULL`.

Scratch and iterator memory is upstream's, not the caller's. Paragraph
resolution and line construction request `MemoryTypeScratch`
(`Source/API/SBParagraph.c:66`, `Source/API/SBLine.c:54`) and reset it before
returning (`SBParagraph.c:665`, `SBLine.c:286`), so `resetScratch` runs on the
calling thread only, and a custom allocator that implements scratch has to make
that thread-local itself (`Headers/SheenBidi/SBAllocator.h:69-70`).

`SBAllocatorGetDefault` returns the stored pointer, which is `NULL` when no
custom allocator is installed (`Source/API/SBAllocator.c:271-274`). The
built-in allocator used in that case is a `static` object (`:187-189`) that none
of these functions ever returns.

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
| `.{ .explicit = 0 ... 125 }` | an explicit level. `0` through `124` are used verbatim as the level the paragraph is resolved against; `125` is accepted by the type and resolved through P2 and P3 exactly as `.auto_ltr` is — see below |

`DetermineParagraphLevel` (`Source/API/SBParagraph.c:256-265`) dispatches on
`baseLevel >= SBLevelMax`, using the value only to pick the P3 fallback when it
takes that branch, so:

* an explicit level is used **verbatim** for `0` through `124`, and the level
  survives into `Paragraph.baseLevel()` unchanged;
* **125 is the boundary**: `level_max` is inside the accepted range of the
  type, but upstream reads `>= 125` as "not explicit" and resolves it through
  P2 and P3, with a left-to-right fallback because `125` is not
  `SBLevelDefaultRTL`. An explicit `125` therefore behaves exactly as
  `.auto_ltr` does — a right-to-left text comes back as level `1`, and a text
  with no strong character comes back as `0` — and never as an explicit level
  of `125`. That is upstream's dispatch, kept as it is rather than corrected;
* an explicit level above `125` is `Error.InvalidBaseLevel` — there is nothing
  left to hand upstream, and the three sentinels `0xFD`–`0xFF` are above it too;
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

* **`-Dlinkage=static|dynamic`** — **added by this migration**,
  `PENDING-VERIFICATION`. Selects which artifact `zig build` produces:
  `libSheenBidi.a` or `libSheenBidi.so`. The default is `static`, which is what
  this package has always produced; nothing about the compiled C changes with
  it. A shared build is a real shared object — position-independent code, real
  exports, and a genuine dependency closure — not a renamed archive. "Static"
  here means a static library artifact and nothing more: SheenBidi calls
  `malloc`, `free`, `memcpy` and `memmove`, so no configuration of this package
  produces a wholly static executable, and no document in this package claims
  one.
  **One asymmetry, on purpose.** `dynamic` also defines the DLL macros upstream's
  CMake defines for a DLL build (`CMakeLists.txt:123-127`): `SB_CONFIG_DLL_EXPORT`
  on the C compile line and `SB_CONFIG_DLL_IMPORT` on the translation line, in
  bundled and `-fsys=sheenbidi` mode alike. They are keyed to the artifact kind,
  not to the target, because `SB_PUBLIC` expands to
  `__declspec(dllexport)`/`__declspec(dllimport)` only under `_WIN32`
  (`Headers/SheenBidi/SBBase.h:30-42`) and is empty everywhere else. The two
  lines never carry the same macro, and `zig/translate.h` defines no
  `SB_CONFIG_*` at all, so each is defined exactly once and on exactly one
  command line. In `-fsys=sheenbidi` the macro follows `system_linkage` rather
  than `linkage`, because that mode builds no artifact of ours, and
  `preferred_link_mode` follows the same value, so the header decoration and the
  linker cannot describe two different libraries. Under the default `static`
  neither macro is defined.

* **`-Druntime=true`** — **added by this migration**, `PENDING-VERIFICATION`.
  Described in the next section. It still compiles and installs exactly what
  `-Dlinkage` asked for and drops only the link: `c` becomes a generated
  dispatch and the facade is not linked against `libSheenBidi`. Delivery and
  dispatch are separate knobs and neither rewrites the other. `zig build` also
  installs `bin/misuse` (`runtime/misuse.zig`) in every configuration.
  The two options are orthogonal, so all four pairings are real configurations
  and CI builds each: `-Druntime` never changes what is installed, and
  `-Dlinkage` never changes what the facade is bound to.

## Runtime loading and the ABI it needs

**Added by this migration. Partly observed on 2026-10-04.** The eight `loaded`
receipts ran `-Druntime=true` with `SHEENBIDI_PROVIDER` set to a separately built
`libSheenBidi.so`, across both linkages and all four optimize modes, and all
exited 0 — so a successful load through the generated dispatch is a recorded
fact. Everything narrower is still a contract: no failed load, retry,
idempotence check or provider change has run, and no `bin/misuse` observation
has. What follows is the contract this configuration is held to, and the ABI a
loaded image must satisfy; see
[Verification status](#verification-status) for which rows moved and which did
not.

`-Druntime=true` builds the facade against a generated dispatch that routes the
selected native externs through a resolved table instead of calling the
translated C directly. In that configuration:

* the facade **does not link** this package's own artifact. The artifact is
  still compiled and still installed — a native delivery choice and the dispatch
  mechanism are separate, and neither implies the other.
* the translated native type and constant namespace is **retained**: the
  generated dispatch holds the same declarations, reached by the same names.
  There is no second, nominally distinct copy of the native structs to cast
  between.
* the root exports the loader's surface for this configuration only:
  `load(LoadSource) LoadError!void`, `LoadSource` (`.path` names a file,
  `.system` an explicit name for the platform loader) and `LoadError`, plus
  `loadedSource()`. In the ordinary linked configuration the module is used as
  described above, with no loader in the picture — and calling `load` there is
  an immediate panic rather than a silent no-op.

### The pairing that needs an explanation

`-Druntime=true -Dlinkage=static` installs `lib/libSheenBidi.a` *and* makes the
program load a shared object built separately from this same source tree. That is
not a contradiction: what this build installs and what the loader opens are two
different facts. It is the compatible-external-provider case the runtime route
exists for — the dispatcher was compiled against this tree's headers, the image
came from another build of the same revision. A 32-bit provider in a 64-bit
process still cannot work, and nothing in the loader can detect that; see the
first ABI point below.

### The misuse observation

What a call before a successful load does cannot be observed from inside the test
binary that causes it — a panic stops the process. `runtime/misuse.zig` is that
observation: a small program installed as `bin/misuse` in **every**
configuration, run as a child process, with three observations —

```sh
./bin/misuse pre-load           # stops: the call arrived before any load
./bin/misuse after-load <path>  # succeeds: the same call after a real load
./bin/misuse linked-load        # stops: a linked build has nothing to load
```

`after-load` is the control: without it, a stop in `pre-load` would be
indistinguishable from a build that is broken for some other reason. The call is
`versionString`, which reaches `SBVersionGetString` and nothing else. CI builds
all four pairings and runs these three; **no CI run of this package has been
executed here**, so no hosted-runner result is claimed.

### What the loader guarantees

One global table per configured module instance, living to process exit. There is
no owning `Library` object and no API view to keep alive: a caller loads once,
explicitly, and then makes ordinary module calls.

* **Explicit source, no fallback.** The source is either an explicit absolute
  file path or an explicit system basename. There is no path-to-system fallback:
  asking for a basename never silently becomes a search of the system, and
  asking for a path never silently resolves to something else.
* **Publication is atomic and the state is checked.** The table is published
  only when every selected symbol resolved and the library validated, and only
  then does it read as ready. A reader that finds it not ready — in **every**
  optimize mode, ReleaseFast and ReleaseSmall included — is a programming error
  and panics rather than calling through a null slot. A failed candidate closes
  itself and publishes nothing.
* **Retries are explicit.** A failed load is not retried automatically. A caller
  may ask again; a caller that has not asked again gets the same failure.
* **Idempotence and provider change.** The same request twice is the same
  request. A different request after a successful one is rejected rather than
  served. Successful handles and a copy of the chosen request live until the
  process exits.
* **Concurrency.** A call that arrives while an attempt is in progress waits for
  *that* attempt and receives its result, not the result of a later one.
  Waiters on a failed attempt drain before a new attempt may start, so two
  attempts never overlap in a way that could publish twice. A reentrant loader
  call on the thread already inside the loader returns an explicit error.
  Native constructors that call back into the loader, and the general
  cross-thread ordering of such a call, remain outside what this contract can
  promise; they are a documented boundary, not a tested path.

### The ABI a loaded image has to satisfy

Resolving a symbol and releasing a handle are not ABI evidence. What has to
hold, read out of upstream's headers and sources:

* **Declarations.** The whole public surface is declared by
  `Headers/SheenBidi/SheenBidi.h`; the dispatch routes that surface and nothing
  outside it.
* **Scalar widths.** `SBUInteger` is `uintptr_t` and `SBInteger` is `intptr_t`
  (`Headers/SheenBidi/SBBase.h:97-102`), so every offset, length and index
  crosses at the machine-word width of the **target**, not of the provider's
  build host; `SBLLevel`, `SBBidiType`, `SBScript` and `SBGeneralCategory` are
  all `SBUInt8`. A provider built for a 32-bit target and loaded into a 64-bit
  one cannot work, and nothing in the loader can discover that.
* **Struct layout, all five by pointer.** `SBCodepointSequence`
  (`SBCodepointSequence.h:32-36`), `SBAllocatorProtocol`
  (`SBAllocator.h:108-136`), `SBRun` (`SBRun.h:28-32`), `SBScriptAgent`
  (`SBScriptLocator.h:31-35`) and `SBMirrorAgent` (`SBMirrorLocator.h:31-36`)
  cross the boundary by pointer, so their field order and padding are part of
  the contract. None has a configurable field, so a provider built from any
  revision of these headers at this pin agrees with them.
* **Handles do not cross images.** `SBAlgorithmRef`, `SBParagraphRef`,
  `SBLineRef`, `SBScriptLocatorRef`, `SBMirrorLocatorRef` and `SBAllocatorRef`
  are opaque handles to objects the provider owns, and retain/release must be a
  real count: the facade hands out one handle per `create` and per `retain`. The
  mirror locator's retain of a line (`Source/API/SBMirrorLocator.c:57`) and the
  paragraph's retain of its algorithm (`Source/API/SBParagraph.c:658`) are what
  the lifetime rules rest on. Create, use and release through one image; mixing
  a loaded copy with a linked copy is undefined in both directions.
* **Callback structures.** `SBAllocatorProtocol` is a struct of six function
  pointers, each taking a `void *info` context
  (`Headers/SheenBidi/SBAllocator.h:108-136`), and is passed **by pointer**.
  The header requires only `allocateBlock` and `deallocateBlock`; the
  implementation calls `reallocateBlock` unconditionally wherever a `List`
  grows, so `NULL` there is a null call and not a fallback. See
  [Redirecting the native allocator](#redirecting-the-native-allocator).
* **The default allocator is process-global and its lifetime is the caller's.**
  `SBAllocatorSetDefault` stores into a single `static` atomic pointer and does
  not retain, so the caller owns the allocator's lifetime; nothing records which
  allocator an object came from, because allocate and free each resolve whatever
  is current at that moment. A process that swaps the default while objects are
  live frees them through a different allocator than they were created with.
  This is the sharpest constraint on any dispatch, linked or loaded: the default
  in force at creation must still be in force at the last release. A custom
  allocator that implements `allocateScratch` must make its scratch per-thread
  itself, because the core resets scratch on the calling thread only.
* **All fifty-one public functions, and no data.** A provider must export every
  `SB_PUBLIC` declaration of the headers `zig/translate.h` reaches in this
  configuration — the full list, with its header and line, is in
  `runtime/library.zig:14-34` — and exports no data symbol at all: the two tables
  behind the code point queries are internal to `Source/Data/`. The seven
  headers behind `SB_TEXT_API_SUPPORTED` are not an optional set here; they do
  not exist on either side of the boundary in this configuration.
* **No variadic entry point**, so a dispatch has none to reproduce, and no data
  to copy: anything a consumer needs from a loaded image is reached by address
  inside that image.

**What is deliberately not a requirement.** Which Unicode revision a provider's
tables were built from. Nothing in the headers selects one, so two providers that
agree on the four points above can still disagree about a code point introduced
after the older was built. The conformance fixtures in `Tools/Unicode/` bound
this package's own answer, not a provider's.

**What is checked at load time.** After every symbol resolves and before anything
is published, `runtime/library.zig`'s `validate` makes observations that are
properties of the ABI rather than of a Unicode revision: `SBVersionGetString()`
answers a NUL-terminated string that is neither empty nor unbounded;
`SBCodepointGetBidiType('A')` is `SBBidiTypeL` and `SBCodepointGetScript(U+05D0)`
is `SBScriptHEBR`, values that have held in every revision SheenBidi has shipped;
and `SBAlgorithmCreate` accepts an `SBCodepointSequence` this build laid out
itself and returns an object real enough to release. Those are checks, not proof:
resolving fifty-one symbols shows the file is a SheenBidi of some build, and
nothing walks a type the provider declared, because it declares none.

### What is not claimed

The load itself is observed: the eight 2026-10-04 `loaded` receipts each print
`configuration: loaded` and exit 0. Everything else in this section is still a
contract rather than a result — no load of a *compatible external provider*
distinct from the separately built image those receipts used, no misuse
observation (`pre-load`, `after-load`, `linked-load`), no startup check, no
failure path, no retry, no idempotence check, no provider-change rejection, and
no release-mode panic check. Those are the driver's remaining gates for this
migration, and until one of them runs with its receipt recorded in
[Verification status](#verification-status), each statement here about it is a
contract.

## The installed C contract

`zig build --prefix <dir>` writes the library, every public header, and —
**added by this migration**, and now observed on 2026-10-04 — the licence and
provenance documents, the Unicode data files they cover, and
`lib/pkgconfig/SheenBidi.pc`:

```
<dir>/lib/libSheenBidi.a              static, the default; with -Dlinkage=dynamic,
                                    libSheenBidi.so.3.0.0 plus the libSheenBidi.so.3
                                    and libSheenBidi.so names, SONAME libSheenBidi.so.3
                                    (upstream CMakeLists.txt:143-147); on Windows
                                    bin/SheenBidi.dll and lib/SheenBidi.lib
<dir>/include/SheenBidi/*.h           upstream's 23 public headers, unedited
<dir>/lib/pkgconfig/SheenBidi.pc      pkg-config metadata, from build.zig; the
                                      base name is the library name, and prefix
                                      is ${pcfiledir}/../..
<dir>/bin/misuse                      the misuse executable, in every configuration
<dir>/share/doc/sheenbidi/…           LICENSE, NOTICE.md, FORK-LICENSE.md,
                                      README.md, README.upstream.md, README.zig.md,
                                      UPSTREAM.md, UPSTREAM.sha256, CHANGELOG.md,
                                      FORK-NOTES.md
<dir>/share/doc/sheenbidi/unicode/    the eleven Tools/Unicode/*.txt data files,
                                      unmodified, with their own terms intact
```

The **link inputs** a C consumer needs are still exactly the first two lines:
the archive and the include directory. Everything under `share/doc` is material
a recipient has to be able to read and audit, not something a compiler reads —
which is why the eleven Unicode files travel there rather than into a data
directory: their terms are named inside the files themselves, and a recipient of
the built package must receive those terms with the data.

The headers are installed *into* the include path rather than beside the
archive, so `-I <dir>/include` is the whole search path a C caller needs, and
`#include <SheenBidi/SheenBidi.h>` — the aggregate header, spelled exactly as
`zig/translate.h` spells it — is the one thing such a program has to include.
No configuration macro is passed to the consumer and none is needed: the only
`SB_CONFIG_*` the core is compiled with is `SB_CONFIG_UNITY`, which turns
`SB_INTERNAL` into `static` for the library build and says nothing about a
consumer's view of the headers, and `Headers/SheenBidi/SBConfig.h` ships every
macro commented out.

Those two link paths are observed, not merely described. The driver installed to a
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

## Nix and devenv

**Added by this migration. Status: `PENDING-VERIFICATION`** — no derivation has
been built and no devenv shell has been entered under a gate in this workspace,
so what follows describes the packaging, not a result.

### devenv is the canonical development environment

```sh
devenv shell                 # or: direnv allow, via .envrc
devenv build outputs.static  # the same package.nix the flake uses
devenv build outputs.shared
```

`devenv.nix` is deliberately light: it supplies the **tools** — the Zig 0.16.0
compiler and pkg-config — and nothing else. The SDK is not a shell package, so
entering the shell never compiles SheenBidi. Namespaced `sheenbidi:*` tasks
(`build`, `test`, `smoke`, `check`, `install`, `consumer`, `integrity`) run this
package's own build graph on demand, against this working tree. `build` and
`install` write to an external `--prefix` beneath the exported
`ZIG_LOCAL_CACHE_DIR`, else `$XDG_CACHE_HOME`, else `$TMPDIR`, so no task writes
`zig-out/` into this checkout; `test`, `smoke`, `check` and `consumer` install
nothing at all, because their steps never reach `b.getInstallStep()`. A caller's
own `--prefix`, arriving in the task's `"$@"`, still overrides that default.

**Every task that reaches `zig build` fixes its job count and its cache.**
`build`, `test`, `smoke`, `check`, `install` and `consumer` each pass a literal
`-j8` and a literal `--cache-dir`, always ahead of the caller's `"$@"`, so no task
takes its parallelism from whatever the machine offers and no task keeps its
build cache at a build root in this checkout. `--cache-dir` names
`$ZIG_LOCAL_CACHE_DIR`, and the same snippet fills that from `$XDG_CACHE_HOME`
else `$TMPDIR` when the caller exported none, exports `ZIG_GLOBAL_CACHE_DIR` the
same way, and creates both before zig starts — in the task body, because
`devenv tasks run` does not run `enterShell`. A caller that exported either
variable keeps its own value. `integrity` runs `sha256sum` and reaches no build
at all. `devenv tasks run` on devenv 2.4 takes no trailing argument, so `"$@"`
is empty on that route. See `CHANGELOG.md` entry 33.

**Each task locates this checkout itself.** devenv generates a task wrapper with
the *project* directory as its working directory when the environment is entered
with `--from path:<this SDK>`; `DEVENV_ROOT` names that project, and
`devenv tasks run` does not run `enterShell` either. Every exec therefore
changes into a path this `devenv.nix` evaluates — `builtins.toString ./.`,
quoted with `lib.escapeShellArg` — before it runs anything. On 2026-10-04,
before that, `sheenbidi:consumer` and `sheenbidi:integrity` failed with
`cd: consumer: No such file or directory` and
`sha256sum: UPSTREAM.sha256: No such file or directory`; neither ran `zig`. See
`CHANGELOG.md` entry 32.

`outputs.static` and `outputs.shared` are the *same* `package.nix` the flake
uses, exposed as lazy devenv outputs: nothing is evaluated until a build asks
for one. `devenv build outputs.static` is therefore the packaging route from
inside a shell, and it is a real build, not a command that echoes what a build
would do.

**State placement is the caller's.** Supply `TMPDIR`, `DEVENV_HOME`,
`XDG_RUNTIME_DIR` and both Zig caches on approved local scratch before entering
the shell; `devenv` otherwise puts its runtime sockets under `/tmp`. This file
hard-codes no mount, account or store path, and it erases none of those
variables — which is also why it cannot promise where any state ended up. What
is true of the file is only this: it adds no path of its own.

No task reaches that state now: all six that run `zig build` name `--cache-dir`
explicitly and fill both Zig cache variables before the compiler starts, so none
of them writes `.zig-cache/` here or under `consumer/`. A bare `zig build` typed
by hand in this checkout still does, and `.gitignore` excludes that directory in
both places, which is what entries 14 and 32 record. That is the whole extent of
what a build can leave behind in this checkout: nothing else is written here.

A `flake.lock` is present in this working copy, pins `nixpkgs` to the same commit
`flake.nix` names, and ships in `build.zig.zon` `.paths`, so a fetched copy
carries the pin its flake declares; no `devenv.lock` exists here and none is
listed. No file of this package writes either one, and `.gitignore` deliberately
ignores neither. The derivation filters both out of the source it hands the
build, which is a separate axis and not a defect: `zig build` never reads a lock
file, so it is the build's input rather than the package's contents, and the Nix
flake frontend has already resolved the locked inputs by the time the derivation
runs. `devenv.yaml` pins its nixpkgs input by commit rather than by a floating
branch name.

### Nix is the delivery, and it is two variants of one derivation

`package.nix` is one uncurried derivation returning **one** result, with
`linkage` as its only variant parameter; `flake.nix` and `devenv.nix` are the two
places the variants exist. It imports nothing from a sibling workspace, names no
host path, downloads nothing, and adds no C flag: `-std=c90`, `-DSB_CONFIG_UNITY`
and the absence of the experimental text API are decided by `build.zig` and stay
decided there. It filters version control, caches, previous outputs, devenv state
and `result` links out of the source it hands the build; everything the build
compiles, installs and tests stays.

The derivation is install-only (`dontBuild`, `dontConfigure`, `dontCheck`, and
**not** `dontInstall`, which would disable the real install phase). Inside that
one phase it exports both Zig caches under the Nix-provided `TMPDIR`, outside the
unpacked source, and passes `-j"${NIX_BUILD_CORES:-1}"`, one optimize selection,
`-Dcpu=baseline`, `-Dlinkage=<variant>` and `--prefix "$out"` to a single
`zig build`. There is no second invocation with different flags.

```sh
nix build .#static     # $out/lib/libSheenBidi.a
nix build .#shared     # $out/lib/libSheenBidi.so
nix build .#default    # == static, this package's existing linkage policy
```

`build.zig` is the only writer of the installed closure: library, all 23 public
headers, the licence and provenance documents, the Unicode data files and
`lib/pkgconfig/SheenBidi.pc`. The derivation adds no file of its own and holds no
list of the install's paths, so there is no second place in which any of them can
be described wrongly; what it still contributes is the two assertions that
`linkage` is one of the two values and that Zig is 0.16.0 rather than a floating
toolchain.

That `.pc` file is written from **upstream's own** `sheenbidi.pc.in` with one
value changed: `prefix` is `${pcfiledir}/../..`, relative to the file pkg-config
found, instead of CMake's configure-time absolute path. That is what removed the
old reason for a derivation to write its own — a fixed `$out` needs no fixing —
and with it the duplicate. An earlier version filled the template into a second,
lower-case `lib/pkgconfig/sheenbidi.pc`; both files carried `Name: SheenBidi`, so
one library was described twice and the two disagreed on the only field that
depends on the variant. The graph's file appends
` -DSB_CONFIG_DLL_IMPORT` to `Cflags:` under `-Dlinkage=dynamic`
(`build.zig:972`), where the derivation's substituted empty. So `nix build .#shared`
carries the DLL-import Cflags and `nix build .#static` does not.

**What is observed, and what is still a prediction.** Every `build.zig` claim in
this subsection is observed for the `zig build install --prefix` route: the
2026-10-04 gates installed `lib/pkgconfig/SheenBidi.pc` and nothing else beside
it, the static prefix's file ends `Cflags: -I"${includedir}"` and the dynamic
prefix's ends `Cflags: -I"${includedir}" -DSB_CONFIG_DLL_IMPORT`, both with
`prefix=${pcfiledir}/../..` and `Name: SheenBidi`. No derivation has been built,
so the `nix build` sentences above are source-confirmed and still unverified —
including the claim that `.#static` and `.#shared` differ in `Cflags:`, which
rests on `build.zig:972` and on `-Dlinkage=${linkage}` in `package.nix:88`.

Two boundaries, stated rather than papered over:

* **No wholly static closure is claimed, for any variant.** SheenBidi allocates
  through `malloc`/`free` and copies through `memcpy`/`memmove`, so a consumer
  of `libSheenBidi.a` still links the platform C runtime. `static` describes the
  library artifact, full stop.
* **`SheenBidi.pc` describes the variant it was installed for, and `Libs:` is the
  same either way.** On `_WIN32`, `SB_PUBLIC` expands to
  `__declspec(dllimport)` only when `SB_CONFIG_DLL_IMPORT` is defined
  (`Headers/SheenBidi/SBBase.h:30-42`), which upstream's own CMake adds for a DLL
  build. `build.zig` keys that `-D` to the artifact kind, not the target: a
  `-Dlinkage=dynamic` install writes it into `Cflags:` whatever the target is,
  and a `-Dlinkage=static` install writes nothing. `Libs:` is
  `-L"${libdir}" -lSheenBidi` in both, and no `Libs.private:` line exists at all.
  So the file's `Cflags:` is right for the variant it was installed for and wrong
  for the other one; do not read it as describing a Windows DLL consumer at all.

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

The table that follows is what was observed **before** this migration; the
section after it lists what this migration still owes a gate. Neither is a
result for the other.

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

### Pending verification for this migration

Everything in the table above was observed **before** this migration, against the
package as it stood on 2026-10-03. That remains true of those rows and they are
evidence about the predecessor, not about what is in the tree now. The rows
below describe the current tree: some are now observed, and the rest are not.

**Observed on 2026-10-04.** Sixteen gates ran between 15:09 and 15:20 UTC, all
exit 0, receipted at
`…/contract-physics-lua/current-native-evidence/sheenbidi-current-{native,loaded}-{static,dynamic}-{Debug,ReleaseSafe,ReleaseFast,ReleaseSmall}-…json`
— eight `native` (`-Druntime=false`) and eight `loaded` (`-Druntime=true`), each
across both linkages and all four optimize modes. Each ran
`zig build test smoke install` with `-j8 --summary all` against a scratch
`--prefix`.

| Gate | Command | Status |
|---|---|---|
| static and shared artifacts | `zig build install -Dlinkage=static` and `-Dlinkage=dynamic`, each in Debug, ReleaseSafe, ReleaseFast and ReleaseSmall | **OBSERVED**, exit 0 in all eight cells. Each prints `51/51 steps succeeded` (native) or `52/52 steps succeeded` (loaded) and installs the library. The 2026-10-02 round in the table above predates these changes |
| installed closure | inspect a prefix install: library, 23 headers, the document set, the eleven Unicode files | **OBSERVED** for the document set, the eleven Unicode files and `lib/pkgconfig/SheenBidi.pc` — the install step summary names each of them, and the `sheenbidi-static` and `sheenbidi-shared` prefixes are readable on disk. That `lib/pkgconfig` holds `SheenBidi.pc` and nothing else is observed too |
| runtime loading, the load itself | `-Druntime=true` with `SHEENBIDI_PROVIDER` set to a separately built `libSheenBidi.so`, across both linkages and all four modes | **OBSERVED**, exit 0 in all eight loaded cells. Each prints `configuration: loaded`, runs the suite under a generated dispatch (`sheenbidi-runtime-generate-…` appears in the step tree) and asserts in `smoke`. A successful load is now a recorded fact, not a contract |
| behavioural tests and smoke | `zig build test smoke` | **OBSERVED**, `44/44 tests passed` per invocation — `run test 22 pass (22 total)` twice, Debug and ReleaseSafe. The count is 22 per mode; the `38/38` and `19 per mode` in the table above are the pre-migration figures |
| installed C surface, new closure | compile and run a C program against the installed headers and artifact | **PENDING-VERIFICATION** — the green receipt in the rows above is pre-migration |
| integrity, after the README relocation | `sha256sum -c UPSTREAM.sha256` | **PENDING-VERIFICATION**. The record's `README.md` line became `README.upstream.md` with the digest unchanged and the count still 218; the check has not been re-run |
| pinned native bytes, after the relocation | `git diff --exit-code cfe430e7… -- Headers Source Tests Tools LICENSE CMakeLists.txt Makefile meson.build meson_options.txt README.upstream.md` | **PENDING-VERIFICATION**. The path list must name the preserved README; comparing the fork's own `README.md` against the pinned commit would be a different question |
| `bin/misuse` observations | the three per runtime cell (`pre-load` stops, `after-load` succeeds, `linked-load` stops), the process-lifetime table, explicit path or named-system selection, no fallback, atomic publication, explicit retry, and the pre-initialization check in **every** optimize mode | **PENDING-VERIFICATION**. The 2026-10-04 receipts record `install misuse`, not a run of it. The contract is in [Runtime loading](#runtime-loading-and-the-abi-it-needs) |
| run-step side-effect flag | the same command twice in one cache dir, showing the second run executes rather than being served | **PENDING-VERIFICATION**. `has_side_effects` is set on the smoke and test run steps; the sixteen receipts predate that change, so they are not evidence for it |
| six-target compile check and the full matrix | `zig build check` over the six targets, `cross-test` over the published 53 | **OBSERVED** in the current source epoch — the two rows in [The current source epoch](#the-current-source-epoch) below, with their epochs, receipts and counts. Neither derives a full-suite runtime pass: the baseline ran nothing, and 33 of the 53 cells are `build_only` |
| package materialisation | `zig fetch`, then the integrity check and the consumer inside the fetched copy, after `.paths` gained the packaging files and `flake.lock` | **PENDING-VERIFICATION** |
| canonical devenv shell | `devenv shell`, then each namespaced `sheenbidi:*` task, then `devenv build outputs.static` | **PENDING-VERIFICATION**. Entering the shell must build nothing, and the driver supplies `TMPDIR`, `DEVENV_HOME`, `XDG_RUNTIME_DIR` and the Zig caches on approved scratch |
| Nix delivery | `nix build .#static`, `nix build .#shared`, `nix build .#default`, each inspected, plus the output dependency records | **PENDING-VERIFICATION**. The `.pc` claims in [Nix and devenv](#nix-and-devenv) are source-confirmed and observed for a prefix install; no Nix output has been built or inspected |
| `zig build -fsys=sheenbidi` | — | **never run**, before this migration or in it, at run time or at compile time. Unchanged, and still unclaimed |

### The current source epoch

Four rounds ran against the tree as it stands, each under its own epoch. They
are the current rows; everything dated above describes the tree as it stood on
its own date.

| Gate | Epoch and receipt | Observed |
|---|---|---|
| full 53-platform `cross-test` matrix | `20261004T221720228710Z-45046`, `sheenbidi-53-target-8.json` | green, exit 0: **20 pass, 33 `build_only`, 0 fail** over all 53 published targets, run at `--jobs 8 --build-jobs 8` with `source_unchanged: true`, `jobs_honoured: true`, `corrected_target_executions: 20` and an empty `problems` list. Each of the twenty reports `run=pass tests=44`; each of the thirty-three reports `run=unavailable reason=runtime_unavailable`. **This is twenty runtime passes over fifty-three targets, not fifty-three passes** |
| six-target compile baseline | `20261005T014547Z-797a73f2`, `baseline-sheenbidi-check` | green, exit 0, `failed: false`, `Build Summary: 31/31 steps succeeded`. One invocation with no `-Dtarget` — the graph's own whole-matrix `check` step — with all six triples seen and six step lines each. `runtime_pass_claimed: false`, and `test_pass_lines` is empty because the run printed no test count at all |
| native eight-cell wave | `20261004T233628757747Z-69351` | **8 pass**: both linkages across all four optimize modes, one `zig build test smoke install -Druntime=false -j8 --summary all` each, exit 0, `51/51 steps succeeded`, `44/44 tests passed`, `tests_skipped: 0`, with `install`, `smoke` and `test` step markers present |
| own-loaded eight-cell wave | `20261004T232823091897Z-23133` | **8 pass**: the same eight cells with `-Druntime=true`, exit 0, `52/52 steps succeeded`, `44/44 tests passed`, `tests_skipped: 0`. Each names `SHEENBIDI_PROVIDER` and reads nothing ambient; the image every cell loaded is this SDK's own source-built one — `kind: own`, resolving to `libSheenBidi.so.3.0.0` |

`44/44` is twenty-two tests in Debug and the same twenty-two in ReleaseSafe,
from one `zig build test`, so it is never a single-mode count. The `38/38` and
the `19 per mode` in the table above are the pre-migration figures and remain
correct for their own date.

**None of the above is a full-suite runtime pass across the 53 targets.** Twenty
cells executed a binary; thirty-three compiled and linked and are reported as
`build_only`, which this harness records as `runtime_unavailable`. "53 targets
built" is not 53 runtime passes, and nothing here describes it as one.

**Two items an earlier diagnostic wave raised, and they are not the same
item.** The build graph now resolves the host before it dispatches:
`isThisMachine` (`build.zig:762-770`) reads the resolved host's architecture,
operating system and ABI, and `build` refuses `-fsys=sheenbidi` under a foreign
`-Dtarget` rather than binding a library installed on this machine to a target
this machine is not (`build.zig:1069-1073`). `Query.isNative()` cannot answer
that question — it is false for every named target — which is why the host is
resolved rather than inferred. `check`'s own dispatch still asks
`target.query.isNative()` (`build.zig:1263`); that is the different question
"was a target named?", and it is unchanged. This is a real change in this
package's own graph and it is **applied**, and **no receipt in this section was
taken after it landed**, so it is **not yet re-gated**. Separately, the same
wave reported the *path of the selected header* incorrectly. That is a gap in
the observing tool, not a defect in this package and not an SDK failure: this
package's own semantic cells exited 0. One observer correction, now frozen,
covers it together with the SheenBidi relative-header handling and the nested
diagnostic and `INSTALL` observer handling; no run has happened since that
correction was frozen, so no result of it is claimed or predicted here.

**Why the `test` row names two receipts, and what `38/38` counts.** This
paragraph and the two paragraphs after it describe the **pre-migration**
receipts in the table above and are kept as they were recorded. The `test` step
builds and runs `tests.zig` in Debug and in ReleaseSafe itself, so each
invocation carries `run test 19 pass (19 total)` twice, once per mode, under a
single `Build Summary: 11/11 steps succeeded; 38/38 tests passed`. There are two
receipts because the step was invoked twice; `-Doptimize` does not narrow it, so
the second invocation ran the same two binaries. **Neither receipt is a
single-mode count**: `38/38` is nineteen tests in Debug plus the same nineteen
in ReleaseSafe, and reading either receipt as "38 in Debug only", or as "38 in
ReleaseSafe only", is reading a number this build never produced.

**That count has since changed, and both figures are correct for their own
date.** `tests.zig` now holds **22** test blocks, so the 2026-10-04 receipts
print `44/44 tests passed` as `run test 22 pass (22 total)` twice. The
arithmetic rule is unchanged and is the one that matters: a single `zig build
test` reports both modes together, so it is never a per-mode number, and neither
nineteen nor twenty-two is a count of a single optimize mode. The three extra
tests were added by the migration; the conformance replays and the boundary
cases they check are still in the file.

**What the green `test` receipts establish** *(the pre-migration pair; the
2026-10-04 equivalents are in the current rows above and report 22 per mode)*.
All nineteen tests pass in both
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
artifact for every mode it builds (`build.zig:1238-1244`), so a cell with a
runner executes every test in that mode — nineteen per mode on 2026-10-02,
twenty-two on the current tree — and a cell without one still compiles them.
When the harness declines to run a foreign binary it replaces that run step's
action with a skip and leaves its compile dependencies in place
(`run_policy.zig:55-57`, `:103-105`), so the cell is `build_only` — compile
evidence, never a pass.

`cross-test.profile.sh` sets `CROSS_BUILD_STEP=test`, `CROSS_BUILD_JOBS=2`,
`CROSS_BUILD_TIMEOUT=3600` and `CROSS_TIMEOUT=1800`. It defines no hooks, no
matrix and no host path, every value is a default the command line overrides,
and `CROSS_LIBC_RUNTIMES` is deliberately left to the environment: it names
foreign libc loaders on the machine running the harness, not something this
package knows.

**How to read a count.** One cell that runs prints a per-mode pair, for the
same reason the native `test` row does. On 2026-10-02 that was `38/38 tests
passed`: nineteen in Debug and the same nineteen in ReleaseSafe, from one
`zig build test`, and never "38 in Debug". On the current tree the same cell
prints `44/44` — twenty-two in Debug and the same twenty-two in ReleaseSafe —
because this migration added three test blocks. The nineteen were both UAX #9
replays, the representative check and the sixteen boundary cases; the
twenty-two are those plus the migration's three, and no cell is allowed to run
a subset of them under either count.

**Observed.** The final run of 2026-10-02 is `cross-test --jobs 2 --build-jobs
2 --build-timeout 3600` from this directory, with `cross-test.profile.sh`
sourced and no command-line override of the deadlines the profile sets; harness
run id `20261002-062101-65268-4429`, `--test-timeout 1800s` per cell. It
covered all 53 published targets and exited **0**: **20 pass, 33 build_only, 0
fail**, `status: partial` because a `build_only` cell is not a pass.

**The current epoch repeats it.** `20261004T221720228710Z-45046`, receipt
`sheenbidi-53-target-8.json`, harness run id `20261005-003057-68533-26669`, run
from this directory at `--jobs 8 --build-jobs 8` — the eight-job shape rather
than the two-job one above — with `build_timeout_seconds: 3600` and
`run_timeout_seconds: 1800` from the same profile. It covered the same 53
published targets and exited **0**: **20 pass, 33 `build_only`, 0 fail**, with
`source_unchanged: true`, `jobs_honoured: true`, `corrected_target_executions:
20` and an empty `problems` list. The same twenty triples ran and the same
thirty-three did not. Each passing cell reports `tests=44`, the current count,
against the `38/38` printed on 2026-10-02; each `build_only` cell still reports
`run=unavailable reason=runtime_unavailable`, and `status` is still `partial`
because a `build_only` cell is not a pass. **No coverage moved between the two
runs, and neither of them is fifty-three runtime passes.**

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

Four things are still unobserved, and no result is claimed for any of them.

| Item | State |
|---|---|
| replaying `git archive` against `9bdf0c279f…cac4a28` | **not run.** It needs a re-fetch of upstream, which this workspace does not have. The digest is the driver's, recorded at import time in [`UPSTREAM.md`](UPSTREAM.md). The 218-record `sha256sum -c` above establishes this tree against the record; it does not establish the tree against upstream |
| `zig build -fsys=sheenbidi` | **not run.** It needs an installed `libSheenBidi` at this manifest's pinned 3.0.0 with its own matching header, and none is available here |
| the package round **after** `cross-test.profile.sh` — filtered fetch, source/fetched integrity and fetched consumer | **Driver-owned closure proof.** The current result and package identity are in the workspace ledger's `cross_test_wave.materialized_packages.sheenbidi` and `local://foundation-cross-test-package-regression.json`. The historical rows above predate the profile. Final identities stay outside package-local documents, which contribute to those identities |
| an independent external provider for the loaded route | **not observed, and none accepted.** The route wave `20261004T232439Z` (`sheenbidi-index.json`) records `external_successes_observed: 0`, `own_routes_counted_as_external: []` and thirteen refusals, and no route in the file carries `counts_as_external_coverage: true`. The one route that succeeded was this SDK's own source-built `libSheenBidi.so.3`; each external candidate was an expected refusal — a library that does not export the fifty-one `SB_PUBLIC` functions a provider has to supply. Both eight-cell waves above are therefore own-provider evidence |

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
and their two `.in` templates, `LICENSE` and `README.upstream.md` — and nothing else, so
the same command works in a clone and in an unpacked package. That includes the
Unicode fixtures the test root embeds and the Apache-2.0 text, not just the
sources the build compiles. See [`UPSTREAM.md`](UPSTREAM.md) for how the
digests were produced and what they do and do not prove.

Run, that check is green: exit 0, 218 records, every line `<path>: OK`
(`…-sheenbidi-immutable-source-integrity-120.log`). The workflow also schedules
it, at `.github/workflows/verify.yml:83-84`, ahead of `zig build` — that is read
out of the file, and **no CI run of this package has been executed here**, so no
hosted-runner result is claimed.

**After this migration the record follows a rename, and its check has not been
re-run.** Upstream's README was this package's `README.md` and is preserved
verbatim as `README.upstream.md`, so that record line changed name and not
digest (`34376a69…ae1c8`) and the count is still 218. The driver's extraction
receipt records the same digest for the preserved file, which is what makes it a
rename rather than a re-hash. **Status: `PENDING-VERIFICATION`.** The green run
above is the run from before the move, and no result is claimed for the check
since.

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
travel unmodified with their notice intact, this package neither restates nor
relicenses them, and they are installed unmodified beside the library with the
terms they carry.

The fork-authored files are licensed under `Apache-2.0` as well, by a **direct
owner authorization** recorded in [`FORK-LICENSE.md`](FORK-LICENSE.md), chosen to
match upstream's primary term; each newly authored source or build file carries
`SPDX-License-Identifier: Apache-2.0`. That authorization post-dates the earlier
records in this package that called the fork's files unassigned and withdrew an
unauthorised Apache-2.0 offer (see [`CHANGELOG.md`](CHANGELOG.md) entries 14, 17
and 18): those were accurate when written, and the authorization is what changed
them. No copyright identity is invented for the fork's additions and none is
attributed to an upstream author.

Attribution, the licence split, the files this fork adds or edits, the installed
closure and the patent-grant termination clause are in [`NOTICE.md`](NOTICE.md).
