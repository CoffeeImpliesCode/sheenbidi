# Zig facade API

This is the compact reference for the facade in `zig/root.zig`. Build and
consumption instructions are in `README.md`.

## Types and constants

| Declaration | Meaning |
|---|---|
| `Level`, `BidiType`, `Script`, `GeneralCategory`, `Codepoint` | Aliases of the translated upstream C types. |
| `CodeUnitIndex` | Unsigned pointer-width index. All offsets, lengths, and indices count code units, not code points. |
| `Run` | A visual-order run with `offset`, `length`, and `level`. |
| `level_invalid`, `level_max`, `level_default_ltr`, `level_default_rtl` | Upstream level constants; `level_max` is 125. |
| `codepoint_invalid`, `codepoint_faulty`, `codepoint_max` | Invalid, replacement, and maximum code point values. |
| `bidi_type_*` | The 24 upstream bidi-type values. |

`versionString() [:0]const u8` returns the linked library's version.

## Sources and decoding

`Source` is a borrowed slice in one of three encodings:

* `Source.fromUtf8([]const u8)`
* `Source.fromUtf16([]const u16)` — native endianness
* `Source.fromUtf32([]const u32)` — native endianness

`Source.codeUnits()` returns its length in the encoding's code units;
`Source.byteLength()` returns its byte length. The slice is never copied or
freed by the facade.

`codepointAt(source, index)` returns `DecodedCodepoint { codepoint, next }`;
`codepointBefore(source, index)` returns `DecodedPreviousCodepoint {
codepoint, start }`. An out-of-range index returns `codepoint_invalid` and
leaves the index unchanged. The explicit decoders are
`codepointDecodeNextFromUtf8`, `codepointDecodePreviousFromUtf8`,
`codepointDecodeNextFromUtf16`, and `codepointDecodePreviousFromUtf16`.
Unrecognised input decodes as `codepoint_faulty`, not as an error.

## Lookups

* `codepointIsSurrogate`, `codepointIsValid`
* `bidiTypeIsStrong`, `bidiTypeIsWeak`, `bidiTypeIsNeutral`, `bidiTypeIsFormat`
* `generalCategoryIsLetter`, `generalCategoryIsMark`, `generalCategoryIsNumber`,
  `generalCategoryIsPunctuation`, `generalCategoryIsSymbol`,
  `generalCategoryIsSeparator`, `generalCategoryIsOther`
* `codepointGeneralCategory`, `codepointBidiType`, `codepointMirror`,
  `codepointScript`
* `scriptUnicodeTag`, `scriptOpenTypeTag`

Script tags are big-endian `u32` values. `scriptUnicodeTag` returns `0` when
its table has no tag; `scriptOpenTypeTag` uses the OpenType `DFLT` tag for
unnamed scripts. The two results are not interchangeable.

## Errors and base levels

`Error` contains `EmptySource`, `RangeOutOfBounds`, `EmptyRange`,
`InvalidBaseLevel`, `OutOfMemory`, and `MissingProtocolFunction`. The facade
checks arguments before calling C; a remaining C `NULL` is reported as
`OutOfMemory`. `Line.visualOrder` uses `std.mem.Allocator.Error` instead.

`BaseLevel` is `.auto_ltr`, `.auto_rtl`, or `.explicit: Level`. Explicit levels
0–124 are used as given. Explicit 125 is accepted but upstream resolves it as
P2/P3 with a left-to-right fallback; values above 125 return
`Error.InvalidBaseLevel`.

All range arguments use code units. Out-of-bounds ranges return
`RangeOutOfBounds`. `Algorithm.paragraphBoundary` accepts an empty range;
`createParagraph` and `Paragraph.createLine` return `EmptyRange` for one.

## Objects

| Type | Operations and result |
|---|---|
| `Algorithm` | `create(source)`, `retain`, `deinit`, `bidiTypes`, `paragraphBoundary(offset, suggested)`, `createParagraph(offset, suggested, base)`. |
| `Paragraph` | `offset`, `length`, `baseLevel`, `levels`, `retain`, `deinit`, `createLine(line_offset, line_length)`. |
| `Line` | `offset`, `length`, `runCount`, `runs`, `retain`, `deinit`, `visualOrder(allocator)`. |
| `ParagraphBoundary` | `length` of the first paragraph and its `separator_length` (`2` for CRLF, `1` for CR or LF, `0` when no separator is in range). |

`bidiTypes`, `levels`, and `runs` are borrowed views into their owning object.
`runs` are already in visual order. `visualOrder` returns an allocated slice of
absolute source code-unit indices; release it with the same allocator passed to
the method. It is the facade's only Zig allocation.

## Locators

* `ScriptLocator.create`, `retain`, `deinit`, `load(source)`, `reset`,
  `moveNext`, `run`. `load` borrows the source; keep its code units alive and
  unchanged until the locator is deinitialised or loaded again. `ScriptRun`
  contains `offset`, `length`, and `script`.
* `MirrorLocator.create`, `retain`, `deinit`, `loadLine(line)`, `reset`,
  `moveNext`, `mirror`. It visits mirrored characters in odd-level runs only.
  `Mirror` contains the absolute source `index`, `codepoint`, and `mirrored`
  code point. Loading retains the line, but not its paragraph or source text.

## Ownership

Every `create` and `retain` returns one reference that needs exactly one
`deinit`; copying a Zig struct does not retain it. A `Paragraph` retains its
`Algorithm`. A `Line` does not retain its `Paragraph`, so the paragraph and
source text must outlive the line. A loaded locator also borrows source text;
a loaded `MirrorLocator` retains its line but still requires the paragraph and
text to remain alive. Returned views remain valid only while their owner is
alive.

SheenBidi allocates and frees its objects with its C allocator. `AllocatorRef`
and `AllocatorProtocol` expose the translated allocator types;
`Allocator.create(protocol, info)`, `retain`, and `deinit` manage an allocator
object. `create` requires non-null `allocateBlock` and `deallocateBlock`
callbacks and can return `MissingProtocolFunction` or `OutOfMemory`.

Install an allocator through the raw `c.SBAllocatorSetDefault` API. The default
is process-global and is not retained by the setter; keep it unchanged and alive
until all objects allocated under it are released. Allocation and free each use
the current default.

## Runtime loading and raw C API

`pub const c` exposes the translated C API. `runtime_loaded` reports whether
this module was built with runtime loading. In that configuration,
`LoadSource` is `.path` (a file) or `.system` (an explicit platform-loader
name), and `load(source) LoadError!void` must succeed before any facade call.
There is no fallback, unload, or reset; `loadedSource()` returns the selected
request. Calling `load` in a linked build panics.