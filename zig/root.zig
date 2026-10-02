//! SheenBidi, the Unicode Bidirectional Algorithm (UAX #9), packaged for Zig.
//!
//! The algorithm is not reimplemented here. Every level, run and reorder in
//! this module comes out of the unmodified upstream C in `Source/`, reached
//! through `c`, the module `b.addTranslateC` produces over `zig/translate.h`.
//! What this module adds is the part a C header cannot express: an explicit
//! borrow contract for the source string, bounds checks that happen before a
//! call into C rather than inside it, one honest error for every NULL return,
//! and a visual-order view of a line.
//!
//! ## The borrow contract
//!
//! SheenBidi never copies the text it works on. `SBAlgorithmCreate` stores the
//! `SBCodepointSequence` the caller handed it — a pointer and a length — and
//! reads through that pointer every time it needs a code point, which can be
//! long after the call that created it. Upstream states the rule in
//! `Headers/SheenBidi/SBAlgorithm.h:30`: "The source string inside the code
//! point sequence should not be freed until the algorithm object is in use."
//!
//! A `Source` is that rule made a type. `Algorithm`, `Paragraph` and `Line`
//! each store a copy of the `Source` record, not of the text; the code units
//! stay where the caller put them. So the caller must keep them alive until the
//! last object derived from them is deinitialised. `Line` carries the record
//! for a reason beyond bookkeeping: `SBMirrorLocatorLoadLine` only accepts a
//! buffer that is pointer-identical to the one the line was built from
//! (`Source/API/SBMirrorLocator.c:56`), and silently ignores anything else, so
//! the facade takes the buffer from the line rather than from a second argument
//! the caller could get wrong.
//!
//! ## Reference lifetimes
//!
//! The reference-counted upstream types are reference-counted here too, and the
//! relationship between them is upstream's, not invented:
//!
//!   * `SBAlgorithmCreateParagraph` retains the algorithm
//!     (`Source/API/SBParagraph.c`, `CreateParagraph`), so a `Paragraph` stays
//!     usable after its `Algorithm` is deinitialised.
//!   * `SBParagraphCreateLine` does *not* retain the paragraph
//!     (`Source/API/SBLine.c:255` copies the code point sequence and nothing
//!     else), so a `Line` must not outlive the `Paragraph` it came from.
//!   * `SBScriptLocatorLoadCodepoints` copies the sequence by value
//!     (`Source/API/SBScriptLocator.c:57`), which is another borrow.
//!   * `SBMirrorLocatorLoadLine` retains the line
//!     (`Source/API/SBMirrorLocator.c:57`).
//!
//! `deinit` hands the object back to the upstream release function, which frees
//! it when its count reaches zero. There is no second allocator in this facade,
//! and no hook for one: `SBAllocatorSetDefault` and friends stay reachable
//! through `c` for a caller that wants to move SheenBidi's allocations into a
//! Zig allocator, but the facade deliberately does not expose them, because a
//! global default allocator has no owner here and a leak oracle for it would
//! have to live outside the test framework.
//!
//! ## Bounds
//!
//! The C entry points take unsigned offsets and lengths and normalise them
//! against the source length (`SBUIntegerNormalizeRange`,
//! `Source/API/SBBase.c:32`), which clamps an out-of-range request instead of
//! reporting it, and computes `offset + length` first — an expression that
//! wraps for a large length. Both are checked here instead, with subtraction
//! (`length > total - offset`), which cannot wrap, and an out-of-range request
//! is an error rather than a silent clamp. The checks are ordinary comparisons,
//! live in Debug and ReleaseSafe, and are not compiled out in ReleaseFast.
//!
//! ## Base levels
//!
//! `BaseLevel` distinguishes the two sentinels from a real level, because
//! upstream treats them very differently: `DetermineParagraphLevel`
//! (`Source/API/SBParagraph.c:256`) applies rules P2 and P3 when
//! `baseLevel >= SBLevelMax`, and uses the value verbatim otherwise. The
//! sentinels pass through unchanged, as upstream defines them.
//!
//! ## Visual order
//!
//! `Line.runs` returns runs in *visual* order, which is what `ReorderRuns`
//! (`Source/API/SBLine.c:234`) already did: it applies rule L2 to the run
//! array as the line is built, so the runs are listed in the order they are
//! drawn, left to right. It permutes the run array and nothing else — a run's
//! `offset` and `length` still name the same code units in the source — so a
//! run at an odd level is drawn from `offset + length - 1` down to `offset`.
//! `Line.visualOrder` applies exactly that and returns an explicit permutation
//! of source indices, which is the form a renderer or a test wants.
//!
//! ## Experimental text API
//!
//! Upstream's text-editing API (`SBText`, `SBTextConfig`, `SBTextIterators`)
//! is compiled out by default: `Headers/SheenBidi/SBConfig.h:39` leaves
//! `SB_CONFIG_EXPERIMENTAL_TEXT_API` commented out, and `SBBase.h:44` keys
//! `SB_TEXT_API_SUPPORTED` off that macro. Nothing in this module reaches for
//! it, and no stub stands in for it. The fork builds upstream's default
//! configuration, so the symbols do not exist in the archive to stub.
//!
//! ```zig
//! const sheenbidi = @import("sheenbidi");
//!
//! // "car means " + three Hebrew letters + ".".
//! const text = "car means \u{05D0}\u{05D1}\u{05D2}.";
//! const source = sheenbidi.Source.fromUtf8(text);
//!
//! var algorithm = try sheenbidi.Algorithm.create(source);
//! defer algorithm.deinit();
//!
//! var paragraph = try algorithm.createParagraph(0, source.codeUnits(), .auto_ltr);
//! defer paragraph.deinit();
//!
//! var line = try paragraph.createLine(paragraph.offset(), paragraph.length());
//! defer line.deinit();
//!
//! const order = try line.visualOrder(allocator);
//! defer allocator.free(order);
//! ```

const std = @import("std");

/// Every declaration transcribed from the upstream public headers, with `c`
/// bound to the translated aggregate header. This is the unmodified upstream
/// ABI: the whole stable surface stays reachable from here, including the
/// allocator protocol and the codepoint decoders this facade wraps.
pub const c = @import("c");

// ---------------------------------------------------------------------------
// Types. Each is the upstream typedef, not a new one.
// ---------------------------------------------------------------------------

/// `SBLevel`, `Headers/SheenBidi/SBBase.h:138`: a resolved embedding level.
pub const Level = c.SBLevel;
/// `SBBidiType`, `Headers/SheenBidi/SBBidiType.h:61`.
pub const BidiType = c.SBBidiType;
/// `SBScript`, `Headers/SheenBidi/SBScript.h:256`.
pub const Script = c.SBScript;
/// `SBGeneralCategory`, `Headers/SheenBidi/SBGeneralCategory.h:71`.
pub const GeneralCategory = c.SBGeneralCategory;
/// `SBCodepoint`, `Headers/SheenBidi/SBCodepoint.h:30`.
pub const Codepoint = c.SBCodepoint;
/// `SBRun`, `Headers/SheenBidi/SBRun.h:28`: a run of code units at one level.
pub const Run = c.SBRun;
/// `SBUInteger`, `Headers/SheenBidi/SBBase.h:102`: an unsigned integer as wide
/// as a pointer. Every offset and length SheenBidi publishes is one of these,
/// and every index here counts code units, not code points.
pub const CodeUnitIndex = c.SBUInteger;

/// The version string of the linked C library (`SBVersionGetString`).
pub fn versionString() [:0]const u8 {
    return std.mem.span(c.SBVersionGetString());
}

// ---------------------------------------------------------------------------
// Header macros. These are `#define`s, so `b.addTranslateC` does not publish
// them as values; each is transcribed here with the line it comes from.
// ---------------------------------------------------------------------------

/// `SBLevelInvalid`, `Headers/SheenBidi/SBBase.h:143`.
pub const level_invalid: Level = 0xFF;
/// `SBLevelMax`, `Headers/SheenBidi/SBBase.h:148`: the highest level an
/// explicit embedding can reach. Note that upstream's own base-level dispatch
/// treats this value as "not explicit" (`baseLevel >= SBLevelMax`).
pub const level_max: Level = 125;
/// `SBLevelDefaultLTR`, `Headers/SheenBidi/SBBase.h:153`.
pub const level_default_ltr: Level = 0xFE;
/// `SBLevelDefaultRTL`, `Headers/SheenBidi/SBBase.h:158`.
pub const level_default_rtl: Level = 0xFD;

/// `SBCodepointInvalid`, `Headers/SheenBidi/SBCodepoint.h:35`.
pub const codepoint_invalid: Codepoint = 0xFFFF_FFFF;
/// `SBCodepointFaulty`, `Headers/SheenBidi/SBCodepoint.h:42`: what decoding
/// substitutes for a code point it cannot recognise.
pub const codepoint_faulty: Codepoint = 0xFFFD;
/// `SBCodepointMax`, `Headers/SheenBidi/SBCodepoint.h:49`.
pub const codepoint_max: Codepoint = 0x10FFFF;

/// `SBUInt8InRange`, `Headers/SheenBidi/SBBase.h:116`, transcribed. The
/// subtraction wraps on purpose, exactly as the macro's cast does, so the test
/// still works for an inclusive end of `0xFF`.
fn inRange8(v: u8, start: u8, end: u8) bool {
    return @as(u8, v -% start) <= @as(u8, end -% start);
}

/// `SBUInt32InRange`, `Headers/SheenBidi/SBBase.h:128`, transcribed.
fn inRange32(v: Codepoint, start: Codepoint, end: Codepoint) bool {
    return @as(Codepoint, v -% start) <= @as(Codepoint, end -% start);
}

/// `SBCodepointIsSurrogate`, `Headers/SheenBidi/SBCodepoint.h:62`.
pub fn codepointIsSurrogate(cp: Codepoint) bool {
    return inRange32(cp, 0xD800, 0xDFFF);
}

/// `SBCodepointIsValid`, `Headers/SheenBidi/SBCodepoint.h:76`: a Unicode
/// scalar value.
pub fn codepointIsValid(cp: Codepoint) bool {
    return !codepointIsSurrogate(cp) and cp <= codepoint_max;
}

// ---------------------------------------------------------------------------
// Bidirectional types.
// ---------------------------------------------------------------------------

pub const bidi_type_nil: BidiType = @intCast(c.SBBidiTypeNil);
pub const bidi_type_l: BidiType = @intCast(c.SBBidiTypeL);
pub const bidi_type_r: BidiType = @intCast(c.SBBidiTypeR);
pub const bidi_type_al: BidiType = @intCast(c.SBBidiTypeAL);
pub const bidi_type_bn: BidiType = @intCast(c.SBBidiTypeBN);
pub const bidi_type_nsm: BidiType = @intCast(c.SBBidiTypeNSM);
pub const bidi_type_an: BidiType = @intCast(c.SBBidiTypeAN);
pub const bidi_type_en: BidiType = @intCast(c.SBBidiTypeEN);
pub const bidi_type_et: BidiType = @intCast(c.SBBidiTypeET);
pub const bidi_type_es: BidiType = @intCast(c.SBBidiTypeES);
pub const bidi_type_cs: BidiType = @intCast(c.SBBidiTypeCS);
pub const bidi_type_ws: BidiType = @intCast(c.SBBidiTypeWS);
pub const bidi_type_s: BidiType = @intCast(c.SBBidiTypeS);
pub const bidi_type_b: BidiType = @intCast(c.SBBidiTypeB);
pub const bidi_type_on: BidiType = @intCast(c.SBBidiTypeON);
pub const bidi_type_lri: BidiType = @intCast(c.SBBidiTypeLRI);
pub const bidi_type_rli: BidiType = @intCast(c.SBBidiTypeRLI);
pub const bidi_type_fsi: BidiType = @intCast(c.SBBidiTypeFSI);
pub const bidi_type_pdi: BidiType = @intCast(c.SBBidiTypePDI);
pub const bidi_type_lre: BidiType = @intCast(c.SBBidiTypeLRE);
pub const bidi_type_rle: BidiType = @intCast(c.SBBidiTypeRLE);
pub const bidi_type_lro: BidiType = @intCast(c.SBBidiTypeLRO);
pub const bidi_type_rlo: BidiType = @intCast(c.SBBidiTypeRLO);
pub const bidi_type_pdf: BidiType = @intCast(c.SBBidiTypePDF);

/// `SBBidiTypeIsStrong`, `Headers/SheenBidi/SBBidiType.h:66`.
pub fn bidiTypeIsStrong(t: BidiType) bool {
    return inRange8(t, bidi_type_l, bidi_type_al);
}

/// `SBBidiTypeIsWeak`, `Headers/SheenBidi/SBBidiType.h:71`.
pub fn bidiTypeIsWeak(t: BidiType) bool {
    return inRange8(t, bidi_type_bn, bidi_type_cs);
}

/// `SBBidiTypeIsNeutral`, `Headers/SheenBidi/SBBidiType.h:76`.
pub fn bidiTypeIsNeutral(t: BidiType) bool {
    return inRange8(t, bidi_type_ws, bidi_type_on);
}

/// `SBBidiTypeIsFormat`, `Headers/SheenBidi/SBBidiType.h:81`.
pub fn bidiTypeIsFormat(t: BidiType) bool {
    return inRange8(t, bidi_type_lri, bidi_type_pdf);
}

// ---------------------------------------------------------------------------
// General categories.
// ---------------------------------------------------------------------------

const general_category_lu: GeneralCategory = @intCast(c.SBGeneralCategoryLU);
const general_category_lo: GeneralCategory = @intCast(c.SBGeneralCategoryLO);
const general_category_mn: GeneralCategory = @intCast(c.SBGeneralCategoryMN);
const general_category_me: GeneralCategory = @intCast(c.SBGeneralCategoryME);
const general_category_nd: GeneralCategory = @intCast(c.SBGeneralCategoryND);
const general_category_no: GeneralCategory = @intCast(c.SBGeneralCategoryNO);
const general_category_pc: GeneralCategory = @intCast(c.SBGeneralCategoryPC);
const general_category_po: GeneralCategory = @intCast(c.SBGeneralCategoryPO);
const general_category_sm: GeneralCategory = @intCast(c.SBGeneralCategorySM);
const general_category_so: GeneralCategory = @intCast(c.SBGeneralCategorySO);
const general_category_zs: GeneralCategory = @intCast(c.SBGeneralCategoryZS);
const general_category_zp: GeneralCategory = @intCast(c.SBGeneralCategoryZP);
const general_category_cc: GeneralCategory = @intCast(c.SBGeneralCategoryCC);
const general_category_cn: GeneralCategory = @intCast(c.SBGeneralCategoryCN);

/// `SBGeneralCategoryIsLetter`, `Headers/SheenBidi/SBGeneralCategory.h:76`.
pub fn generalCategoryIsLetter(g: GeneralCategory) bool {
    return inRange8(g, general_category_lu, general_category_lo);
}

/// `SBGeneralCategoryIsMark`, `Headers/SheenBidi/SBGeneralCategory.h:81`.
pub fn generalCategoryIsMark(g: GeneralCategory) bool {
    return inRange8(g, general_category_mn, general_category_me);
}

/// `SBGeneralCategoryIsNumber`, `Headers/SheenBidi/SBGeneralCategory.h:86`.
pub fn generalCategoryIsNumber(g: GeneralCategory) bool {
    return inRange8(g, general_category_nd, general_category_no);
}

/// `SBGeneralCategoryIsPunctuation`, `Headers/SheenBidi/SBGeneralCategory.h:91`.
pub fn generalCategoryIsPunctuation(g: GeneralCategory) bool {
    return inRange8(g, general_category_pc, general_category_po);
}

/// `SBGeneralCategoryIsSymbol`, `Headers/SheenBidi/SBGeneralCategory.h:96`.
pub fn generalCategoryIsSymbol(g: GeneralCategory) bool {
    return inRange8(g, general_category_sm, general_category_so);
}

/// `SBGeneralCategoryIsSeparator`, `Headers/SheenBidi/SBGeneralCategory.h:101`.
pub fn generalCategoryIsSeparator(g: GeneralCategory) bool {
    return inRange8(g, general_category_zs, general_category_zp);
}

/// `SBGeneralCategoryIsOther`, `Headers/SheenBidi/SBGeneralCategory.h:106`.
pub fn generalCategoryIsOther(g: GeneralCategory) bool {
    return inRange8(g, general_category_cc, general_category_cn);
}

/// `SBCodepointGetGeneralCategory`, `Headers/SheenBidi/SBCodepoint.h:96`.
pub fn codepointGeneralCategory(cp: Codepoint) GeneralCategory {
    return c.SBCodepointGetGeneralCategory(cp);
}

/// `SBCodepointGetBidiType`, `Headers/SheenBidi/SBCodepoint.h:86`.
pub fn codepointBidiType(cp: Codepoint) BidiType {
    return c.SBCodepointGetBidiType(cp);
}

/// `SBCodepointGetMirror`, `Headers/SheenBidi/SBCodepoint.h:106`: the mirrored
/// code point, or `0` when the code point is not mirrored.
pub fn codepointMirror(cp: Codepoint) Codepoint {
    return c.SBCodepointGetMirror(cp);
}

/// `SBCodepointGetScript`, `Headers/SheenBidi/SBCodepoint.h:116`.
pub fn codepointScript(cp: Codepoint) Script {
    return c.SBCodepointGetScript(cp);
}

/// `SBScriptGetUnicodeTag`, `Headers/SheenBidi/SBScript.h:291`: the four-letter
/// Unicode script tag as a big-endian `u32`, or `0` when there is none.
pub fn scriptUnicodeTag(script: Script) u32 {
    return c.SBScriptGetUnicodeTag(script);
}

// ---------------------------------------------------------------------------
// Errors.
//
// Every entry names one condition the facade itself established. Upstream has
// no error channel at all: it returns NULL. Because this module checks the
// arguments before handing them over, the NULL that is left is upstream's
// allocation failure and nothing else, and it is reported once as
// `Error.OutOfMemory` rather than given a name it cannot support.
// ---------------------------------------------------------------------------

pub const Error = error{
    /// The source has no code units. `SBCodepointSequenceIsValid`
    /// (`Source/API/SBCodepointSequence.c:36`) requires `stringLength > 0`,
    /// so `SBAlgorithmCreate` returns NULL for an empty sequence.
    EmptySource,
    /// The requested code-unit range does not fit inside the buffer it names.
    /// Upstream would clamp it instead (`SBUIntegerNormalizeRange`).
    RangeOutOfBounds,
    /// The requested range is inside the buffer but covers no code units, which
    /// upstream reports as a NULL paragraph or line.
    EmptyRange,
    /// An explicit base level above `level_max`.
    InvalidBaseLevel,
    /// SheenBidi could not allocate one of its objects. This is the only
    /// remaining reason the C returns NULL once the argument has been checked.
    OutOfMemory,
};

/// Which base level a paragraph is resolved against.
///
/// Upstream takes a bare `SBLevel` and reads `>= SBLevelMax` as "apply P2 and
/// P3". Keeping the sentinels apart from real levels in the type means a caller
/// cannot pass `0xFE` by accident, and cannot pass `0xFF`, which upstream would
/// also read as a default.
pub const BaseLevel = union(enum) {
    /// Rules P2 and P3 with a left-to-right fallback (`SBLevelDefaultLTR`).
    auto_ltr,
    /// Rules P2 and P3 with a right-to-left fallback (`SBLevelDefaultRTL`).
    auto_rtl,
    /// A level in `0...124`, used verbatim: this is the level the paragraph is
    /// resolved against, with rules P2 and P3 skipped.
    ///
    /// `level_max` is the one value inside `0...level_max` that upstream does
    /// *not* take verbatim. `DetermineParagraphLevel`
    /// (`Source/API/SBParagraph.c:258`) reads `baseLevel >= SBLevelMax` as
    /// "apply P2 and P3", with `SBLevelDefaultRTL` as the only exception, so
    /// an explicit `125` is resolved as a left-to-right default sentinel
    /// rather than as an explicit level of 125. Above `level_max` there is
    /// nothing left to hand upstream, which is what
    /// `Error.InvalidBaseLevel` is for.
    explicit: Level,

    /// The `SBLevel` this resolves to, or `Error.InvalidBaseLevel` for an
    /// explicit level outside `0...level_max`.
    pub fn toC(self: BaseLevel) Error!Level {
        return switch (self) {
            .auto_ltr => level_default_ltr,
            .auto_rtl => level_default_rtl,
            .explicit => |l| resolved: {
                if (l > level_max) break :resolved Error.InvalidBaseLevel;
                break :resolved l;
            },
        };
    }
};

/// Which encoding a borrowed source uses. The values are upstream's
/// (`Headers/SheenBidi/SBCodepointSequence.h:25`), read out of the translated
/// constants rather than written down a second time.
pub const Encoding = enum(u32) {
    utf8 = c.SBStringEncodingUTF8,
    utf16 = c.SBStringEncodingUTF16,
    utf32 = c.SBStringEncodingUTF32,
};

/// Borrowed source text, in one of the three encodings `SBCodepointSequence`
/// understands.
///
/// The slices are borrowed, never copied, and must stay alive and unmodified
/// for as long as any `Algorithm`, `Paragraph`, `Line` or loaded
/// `ScriptLocator` refers to them.
pub const Source = union(Encoding) {
    /// Code units of UTF-8.
    utf8: []const u8,
    /// Code units of UTF-16 in native endianness.
    utf16: []const u16,
    /// Code units of UTF-32 in native endianness.
    utf32: []const u32,

    /// Borrows `text` as UTF-8.
    pub fn fromUtf8(text: []const u8) Source {
        return .{ .utf8 = text };
    }

    /// Borrows `units` as native-endian UTF-16.
    pub fn fromUtf16(units: []const u16) Source {
        return .{ .utf16 = units };
    }

    /// Borrows `units` as native-endian UTF-32.
    pub fn fromUtf32(units: []const u32) Source {
        return .{ .utf32 = units };
    }

    /// The length in code units, which is the unit every SheenBidi offset,
    /// length and run is expressed in. It is *not* a count of code points: the
    /// same text is longer in UTF-8 than in UTF-32.
    pub fn codeUnits(self: Source) CodeUnitIndex {
        return switch (self) {
            .utf8 => |units| units.len,
            .utf16 => |units| units.len,
            .utf32 => |units| units.len,
        };
    }

    /// The length of the borrowed buffer in bytes, which is what a caller
    /// holding the text in a `[]const u8` needs in order to reason about it.
    pub fn byteLength(self: Source) usize {
        return switch (self) {
            .utf8 => |units| units.len,
            .utf16 => |units| units.len * @sizeOf(u16),
            .utf32 => |units| units.len * @sizeOf(u32),
        };
    }

    fn buffer(self: Source) ?*const anyopaque {
        return switch (self) {
            .utf8 => |units| @ptrCast(units.ptr),
            .utf16 => |units| @ptrCast(units.ptr),
            .utf32 => |units| @ptrCast(units.ptr),
        };
    }

    fn sequence(self: Source) c.SBCodepointSequence {
        return .{
            .stringEncoding = @intFromEnum(self),
            .stringBuffer = self.buffer(),
            .stringLength = self.codeUnits(),
        };
    }
};

/// The code point at an index and where the next one starts.
pub const DecodedCodepoint = struct {
    /// The decoded code point, or `codepoint_invalid` when the index was
    /// outside the source.
    codepoint: Codepoint,
    /// Index of the first code unit past the code point, or the input index
    /// unchanged when the request was out of range.
    next: CodeUnitIndex,
};

/// The code point ending at an index and where it starts.
pub const DecodedPreviousCodepoint = struct {
    /// The decoded code point, or `codepoint_invalid` when the index was zero
    /// or past the end of the source.
    codepoint: Codepoint,
    /// Index of the first code unit of the code point, or the input index
    /// unchanged when the request was out of range.
    start: CodeUnitIndex,
};

/// `SBCodepointSequenceGetCodepointAt`, with the bounds check hoisted out of
/// the C. An out-of-range index yields `codepoint_invalid` and leaves the index
/// where it was, which is what `Headers/SheenBidi/SBCodepointSequence.h:67`
/// documents.
pub fn codepointAt(source: Source, index: CodeUnitIndex) DecodedCodepoint {
    if (index >= source.codeUnits()) {
        return .{ .codepoint = codepoint_invalid, .next = index };
    }
    const sequence = source.sequence();
    var cursor = index;
    const cp = c.SBCodepointSequenceGetCodepointAt(&sequence, &cursor);
    return .{ .codepoint = cp, .next = cursor };
}

/// `SBCodepointSequenceGetCodepointBefore`, with the bounds check hoisted out of
/// the C. The index may equal the source length, which is how a caller asks for
/// the code point before the end.
pub fn codepointBefore(source: Source, index: CodeUnitIndex) DecodedPreviousCodepoint {
    if (index == 0 or index > source.codeUnits()) {
        return .{ .codepoint = codepoint_invalid, .start = index };
    }
    const sequence = source.sequence();
    var cursor = index;
    const cp = c.SBCodepointSequenceGetCodepointBefore(&sequence, &cursor);
    return .{ .codepoint = cp, .start = cursor };
}

/// Where the first paragraph inside a range ends.
pub const ParagraphBoundary = struct {
    /// Code units of the first paragraph, including its separator.
    length: CodeUnitIndex,
    /// Code units the paragraph separator occupied. `2` for a CRLF pair, `1`
    /// for a lone CR or LF, and `0` when the range ran out before a separator.
    separator_length: CodeUnitIndex,
};

/// A SheenBidi algorithm object over one borrowed `Source`.
pub const Algorithm = struct {
    ref: c.SBAlgorithmRef,
    /// The borrow this object reads through. Kept so that everything derived
    /// from it can name the same buffer, which `SBMirrorLocatorLoadLine`
    /// requires.
    source: Source,

    /// Creates an algorithm over `source`.
    ///
    /// `Error.EmptySource` for a source with no code units;
    /// `Error.OutOfMemory` if upstream cannot allocate. Every other reason
    /// `SBAlgorithmCreate` returns NULL has been ruled out here first.
    pub fn create(source: Source) Error!Algorithm {
        if (source.codeUnits() == 0) return Error.EmptySource;
        const sequence = source.sequence();
        const ref = c.SBAlgorithmCreate(&sequence);
        return .{ .ref = ref orelse return Error.OutOfMemory, .source = source };
    }

    /// Increments the reference count and returns another handle to the same
    /// object.
    pub fn retain(self: Algorithm) Algorithm {
        return .{ .ref = c.SBAlgorithmRetain(self.ref), .source = self.source };
    }

    /// Decrements the reference count, releasing the object at zero.
    pub fn deinit(self: *Algorithm) void {
        c.SBAlgorithmRelease(self.ref);
        self.* = undefined;
    }

    /// The bidirectional type of every code unit of the source.
    ///
    /// This is a view into the algorithm's own storage, not a copy, and it has
    /// one entry per code unit: a multi-byte code point is followed by `BN`
    /// entries for the rest of its code units.
    pub fn bidiTypes(self: Algorithm) []const BidiType {
        const ptr: [*]const BidiType = c.SBAlgorithmGetBidiTypesPtr(self.ref);
        return ptr[0..self.source.codeUnits()];
    }

    /// Applies rule P1 to find the end of the first paragraph in
    /// `[offset, offset + suggested)`, given in code units.
    ///
    /// A CR followed by LF counts as one separator, so the boundary lands after
    /// the LF (`Source/API/SBCodepointSequence.c:52`). A range that fits the
    /// source is accepted even when it is empty, which reports no paragraph and
    /// no separator; `Error.RangeOutOfBounds` for a range that does not fit,
    /// where upstream would clamp it.
    pub fn paragraphBoundary(
        self: Algorithm,
        offset: CodeUnitIndex,
        suggested: CodeUnitIndex,
    ) Error!ParagraphBoundary {
        const total = self.source.codeUnits();
        if (offset > total or suggested > total - offset) return Error.RangeOutOfBounds;
        var actual: CodeUnitIndex = undefined;
        var separator: CodeUnitIndex = undefined;
        c.SBAlgorithmGetParagraphBoundary(self.ref, offset, suggested, &actual, &separator);
        return .{ .length = actual, .separator_length = separator };
    }

    /// Creates the first paragraph in `[offset, offset + suggested)`, given in
    /// code units.
    ///
    /// The paragraph retains this algorithm internally, so it stays usable
    /// after `deinit` is called here.
    pub fn createParagraph(
        self: Algorithm,
        offset: CodeUnitIndex,
        suggested: CodeUnitIndex,
        base: BaseLevel,
    ) Error!Paragraph {
        const total = self.source.codeUnits();
        if (offset > total or suggested > total - offset) return Error.RangeOutOfBounds;
        if (suggested == 0) return Error.EmptyRange;
        const ref = c.SBAlgorithmCreateParagraph(self.ref, offset, suggested, try base.toC());
        return .{ .ref = ref orelse return Error.OutOfMemory, .source = self.source };
    }
};

/// A paragraph with its embedding levels resolved by rules P2-P3 and X1-I2.
pub const Paragraph = struct {
    ref: c.SBParagraphRef,
    /// The borrow the paragraph reads through.
    source: Source,

    /// Index of the first code unit of the paragraph in the source.
    pub fn offset(self: Paragraph) CodeUnitIndex {
        return c.SBParagraphGetOffset(self.ref);
    }

    /// Number of code units in the paragraph, including its separator.
    pub fn length(self: Paragraph) CodeUnitIndex {
        return c.SBParagraphGetLength(self.ref);
    }

    /// The resolved paragraph embedding level. For `BaseLevel.auto_ltr` and
    /// `.auto_rtl` this is the level rules P2 and P3 arrived at, not the
    /// sentinel that was passed in.
    pub fn baseLevel(self: Paragraph) Level {
        return c.SBParagraphGetBaseLevel(self.ref);
    }

    /// The resolved embedding level of every code unit, in source order.
    ///
    /// A view into the paragraph's own storage. Code units that rule X9 removes
    /// are present and carry the paragraph level, which is what rule L1 does to
    /// them (`Source/API/SBLine.c:136`, `ResetLevels`).
    pub fn levels(self: Paragraph) []const Level {
        const ptr: [*]const Level = c.SBParagraphGetLevelsPtr(self.ref);
        return ptr[0..self.length()];
    }

    /// Increments the reference count.
    pub fn retain(self: Paragraph) Paragraph {
        return .{ .ref = c.SBParagraphRetain(self.ref), .source = self.source };
    }

    /// Decrements the reference count, releasing the object at zero.
    pub fn deinit(self: *Paragraph) void {
        c.SBParagraphRelease(self.ref);
        self.* = undefined;
    }

    /// Creates the line covering `[line_offset, line_offset + line_length)`,
    /// given in source code units.
    ///
    /// The line does not retain the paragraph, so the paragraph must outlive
    /// every line made from it.
    ///
    /// `Error.RangeOutOfBounds` for a range that leaves the paragraph;
    /// `Error.EmptyRange` for a range of no code units. Upstream returns NULL
    /// for both.
    pub fn createLine(
        self: Paragraph,
        line_offset: CodeUnitIndex,
        line_length: CodeUnitIndex,
    ) Error!Line {
        const start = self.offset();
        const end = start + self.length();
        if (line_offset < start) return Error.RangeOutOfBounds;
        // Subtraction, not `line_offset + line_length`: the sum wraps, and
        // upstream compares the wrapped sum against the paragraph limit.
        const remaining = if (line_offset < end) end - line_offset else 0;
        if (line_length == 0) return Error.EmptyRange;
        if (line_length > remaining) return Error.RangeOutOfBounds;
        const ref = c.SBParagraphCreateLine(self.ref, line_offset, line_length);
        return .{ .ref = ref orelse return Error.OutOfMemory, .source = self.source };
    }
};

/// One line of a paragraph, with rules L1 and L2 applied.
///
/// The runs are in visual order: `ReorderRuns` (`Source/API/SBLine.c:234`)
/// reverses the contiguous runs at each level from the highest down to level 1
/// as the line is built, so an odd-level run appears with its code units
/// right-to-left. Offsets in a run are absolute indices into the source.
pub const Line = struct {
    ref: c.SBLineRef,
    /// The borrow the line reads through, and the buffer
    /// `MirrorLocator.loadLine` hands upstream.
    source: Source,

    /// Index of the first code unit of the line in the source.
    pub fn offset(self: Line) CodeUnitIndex {
        return c.SBLineGetOffset(self.ref);
    }

    /// Number of code units in the line.
    pub fn length(self: Line) CodeUnitIndex {
        return c.SBLineGetLength(self.ref);
    }

    /// Number of runs, always at least one for a line that exists.
    pub fn runCount(self: Line) CodeUnitIndex {
        return c.SBLineGetRunCount(self.ref);
    }

    /// The line's runs, in the order they are drawn, left to right. A view
    /// into the line's own storage.
    ///
    /// Rule L2 permutes this array but never reverses a run, so a run at an
    /// odd level is drawn from `offset + length - 1` down to `offset`.
    /// `visualOrder` is the form that has already applied that.
    pub fn runs(self: Line) []const Run {
        const ptr: [*]const Run = c.SBLineGetRunsPtr(self.ref);
        return ptr[0..self.runCount()];
    }

    /// Increments the reference count.
    pub fn retain(self: Line) Line {
        return .{ .ref = c.SBLineRetain(self.ref), .source = self.source };
    }

    /// Decrements the reference count, releasing the object at zero.
    pub fn deinit(self: *Line) void {
        c.SBLineRelease(self.ref);
        self.* = undefined;
    }

    /// The code units of the line in the order they are drawn, left to right.
    ///
    /// This expands the visual run order into an explicit permutation of source
    /// indices: an even-level run contributes its code units forwards, an
    /// odd-level run backwards. The result has `line.length()` entries and the
    /// caller owns the allocation.
    pub fn visualOrder(self: Line, allocator: std.mem.Allocator) std.mem.Allocator.Error![]CodeUnitIndex {
        const order = try allocator.alloc(CodeUnitIndex, self.length());
        errdefer allocator.free(order);

        var written: usize = 0;
        for (self.runs()) |run| {
            const run_start = run.offset;
            const run_end = run.offset + run.length;
            if ((run.level & 1) == 0) {
                for (run_start..run_end) |index| {
                    order[written] = index;
                    written += 1;
                }
            } else {
                var index = run_end;
                while (index > run_start) {
                    index -= 1;
                    order[written] = index;
                    written += 1;
                }
            }
        }
        return order;
    }
};

/// A run of code points that share a script.
pub const ScriptRun = struct {
    /// Index of the first code unit of the run in the source.
    offset: CodeUnitIndex,
    /// Number of code units in the run.
    length: CodeUnitIndex,
    /// The script the run resolved to. Punctuation that pairs with mirrored
    /// punctuation inherits the script of the text it encloses, which is why a
    /// script run is not simply the set of code points sharing a Script
    /// property value.
    script: Script,
};

/// Walks the script runs of a borrowed source.
///
/// The locator copies the `SBCodepointSequence` by value
/// (`Source/API/SBScriptLocator.c:57`), so the source it was loaded with must
/// outlive the locator.
pub const ScriptLocator = struct {
    ref: c.SBScriptLocatorRef,

    /// Creates a locator with nothing loaded.
    pub fn create() Error!ScriptLocator {
        const ref = c.SBScriptLocatorCreate();
        return .{ .ref = ref orelse return Error.OutOfMemory };
    }

    /// Increments the reference count.
    pub fn retain(self: ScriptLocator) ScriptLocator {
        return .{ .ref = c.SBScriptLocatorRetain(self.ref) };
    }

    /// Decrements the reference count, releasing the object at zero.
    pub fn deinit(self: *ScriptLocator) void {
        c.SBScriptLocatorRelease(self.ref);
        self.* = undefined;
    }

    /// Loads `source` and rewinds to its first run.
    ///
    /// Loading is a borrow, not a copy: the code units must stay alive and
    /// unmodified until the locator is deinitialised or loaded again. An empty
    /// source is accepted here, unlike `Algorithm.create`, because upstream's
    /// locator has no length check of its own and simply reports no runs.
    pub fn load(self: ScriptLocator, source: Source) void {
        const sequence = source.sequence();
        c.SBScriptLocatorLoadCodepoints(self.ref, &sequence);
    }

    /// The run the locator is currently on, meaningful after a `moveNext` that
    /// returned `true`.
    pub fn run(self: ScriptLocator) ScriptRun {
        // `SBScriptLocatorGetAgent` is declared `const SBScriptAgent *` and
        // returns the address of the locator's own agent
        // (`Source/API/SBScriptLocator.c:64`), which translate-c publishes as a
        // C pointer. It is never null, so the pointee is read directly.
        const agent = c.SBScriptLocatorGetAgent(self.ref).*;
        return .{ .offset = agent.offset, .length = agent.length, .script = agent.script };
    }

    /// Advances to the next run, returning `false` once the source is
    /// exhausted. The locator rewinds itself at the end, so a later call
    /// restarts from the first run.
    pub fn moveNext(self: ScriptLocator) bool {
        return c.SBScriptLocatorMoveNext(self.ref) != 0;
    }

    /// Rewinds to the first run of the loaded source.
    pub fn reset(self: ScriptLocator) void {
        c.SBScriptLocatorReset(self.ref);
    }
};

/// A code point in a line that has a mirrored counterpart.
pub const Mirror = struct {
    /// Absolute index of the code point in the source.
    index: CodeUnitIndex,
    /// The code point that was found.
    codepoint: Codepoint,
    /// Its mirrored counterpart.
    mirrored: Codepoint,
};

/// Walks the mirrored code points of a line.
///
/// Only runs at an odd level are considered: a mirror is applied where the
/// character is drawn right-to-left (`Source/API/SBMirrorLocator.c:78`). The
/// locator retains the line it is given (`Source/API/SBMirrorLocator.c:57`).
pub const MirrorLocator = struct {
    ref: c.SBMirrorLocatorRef,

    /// Creates a locator with nothing loaded.
    pub fn create() Error!MirrorLocator {
        const ref = c.SBMirrorLocatorCreate();
        return .{ .ref = ref orelse return Error.OutOfMemory };
    }

    /// Increments the reference count.
    pub fn retain(self: MirrorLocator) MirrorLocator {
        return .{ .ref = c.SBMirrorLocatorRetain(self.ref) };
    }

    /// Decrements the reference count, releasing the object at zero.
    pub fn deinit(self: *MirrorLocator) void {
        c.SBMirrorLocatorRelease(self.ref);
        self.* = undefined;
    }

    /// Loads `line` and rewinds to its first mirror.
    ///
    /// The buffer comes from `line` itself, not from a second argument.
    /// Upstream ignores a load whose buffer is not pointer-identical to the one
    /// the line was built from (`Source/API/SBMirrorLocator.c:56`), and an
    /// ignored load looks exactly like a line with no mirrors.
    pub fn loadLine(self: MirrorLocator, line: Line) void {
        c.SBMirrorLocatorLoadLine(self.ref, line.ref, line.source.buffer());
    }

    /// The mirror the locator is currently on, meaningful after a `moveNext`
    /// that returned `true`.
    pub fn mirror(self: MirrorLocator) Mirror {
        // As above: `Source/API/SBMirrorLocator.c:65` returns the address of
        // the agent embedded in the locator, so the pointee is always there.
        const agent = c.SBMirrorLocatorGetAgent(self.ref).*;
        return .{ .index = agent.index, .codepoint = agent.codepoint, .mirrored = agent.mirror };
    }

    /// Advances to the next mirror, returning `false` once the line is
    /// exhausted. The locator rewinds itself at the end.
    pub fn moveNext(self: MirrorLocator) bool {
        return c.SBMirrorLocatorMoveNext(self.ref) != 0;
    }

    /// Rewinds to the first mirror of the loaded line.
    pub fn reset(self: MirrorLocator) void {
        c.SBMirrorLocatorReset(self.ref);
    }
};
