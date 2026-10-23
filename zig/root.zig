// SPDX-License-Identifier: Apache-2.0

//! Zig facade for SheenBidi's Unicode Bidirectional Algorithm.
//! Source buffers are borrowed; destroy each library object with `deinit`.
//! Linked mode is default; runtime mode requires an explicit `load` request.
const std = @import("std");

/// Raw upstream C ABI translated from the fork header; facade checks do not apply.
/// Runtime mode exposes the same declarations through the dispatch table.
pub const c = @import("c");

/// Opaque reference-counted allocator handle.
pub const AllocatorRef = c.SBAllocatorRef;
/// Translated allocator callbacks; `allocateBlock` and `deallocateBlock` are required, others optional.
pub const AllocatorProtocol = c.SBAllocatorProtocol;

const rt = @import("rt");

/// Compile-time indicator for linked or runtime-loaded configuration.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Explicit absolute path or bare platform-loader name; requests never fall back between forms.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Errors returned by `load`.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Loads an explicit provider in runtime mode; linked mode panics.
/// Same requests are idempotent; failed attempts return `LoadError` and may be retried.
/// The successful provider stays loaded until process exit.
pub fn load(source: LoadSource) LoadError!void {
    if (comptime !runtime_loaded) {
        std.debug.panic(
            "sheenbidi: load was called on a linked build; this module is not " ++
                "runtime-loaded, so there is no library to load. Build with " ++
                "runtime loading configured, or do not call load.",
            .{},
        );
    }
    return c.load(source);
}

/// Returns the successful request, or `null` when nothing is loaded.
/// The loader-owned request bytes remain valid for the process lifetime.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

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
/// Upstream run record; offsets and lengths count source code units.
/// `Line.runs` returns line-owned storage; do not mutate it.
pub const Run = c.SBRun;
/// Pointer-width unsigned offset or length in source code units.
pub const CodeUnitIndex = c.SBUInteger;

/// Returns the C-owned, sentinel-terminated library version string.
/// It remains valid while the library is loaded.
pub fn versionString() [:0]const u8 {
    return std.mem.span(c.SBVersionGetString());
}

/// Sentinel for an invalid or unresolved embedding level (`0xFF`).
pub const level_invalid: Level = @intCast(c.SBLevelInvalid);
/// Highest explicit level; upstream treats it as an automatic P2/P3 request.
/// `BaseLevel` accepts it, but paragraph resolution does not preserve it.
pub const level_max: Level = @intCast(c.SBLevelMax);
/// P2/P3 fallback level with a left-to-right default.
pub const level_default_ltr: Level = @intCast(c.SBLevelDefaultLTR);
/// P2/P3 fallback level with a right-to-left default.
pub const level_default_rtl: Level = @intCast(c.SBLevelDefaultRTL);

/// Sentinel returned when a decode index is out of range.
pub const codepoint_invalid: Codepoint = @intCast(c.SBCodepointInvalid);
/// Replacement code point returned when the input sequence is malformed.
pub const codepoint_faulty: Codepoint = @intCast(c.SBCodepointFaulty);
/// Highest Unicode code point recognized by the library.
pub const codepoint_max: Codepoint = @intCast(c.SBCodepointMax);

/// Wraparound subtraction transcribes upstream's inclusive range macro.
fn inRange8(v: u8, start: u8, end: u8) bool {
    return @as(u8, v -% start) <= @as(u8, end -% start);
}

/// Transcribes upstream's `SBUInt32InRange` macro.
fn inRange32(v: Codepoint, start: Codepoint, end: Codepoint) bool {
    return @as(Codepoint, v -% start) <= @as(Codepoint, end -% start);
}

/// Returns whether `cp` is in the surrogate range.
pub fn codepointIsSurrogate(cp: Codepoint) bool {
    return inRange32(cp, 0xD800, 0xDFFF);
}

/// Returns whether `cp` is a Unicode scalar value.
pub fn codepointIsValid(cp: Codepoint) bool {
    return !codepointIsSurrogate(cp) and cp <= codepoint_max;
}

/// Unset marker; it belongs to none of the four bidi type families.
pub const bidi_type_nil: BidiType = @intCast(c.SBBidiTypeNil);
/// `SBBidiTypeL`, strong: left-to-right.
pub const bidi_type_l: BidiType = @intCast(c.SBBidiTypeL);
/// `SBBidiTypeR`, strong: right-to-left.
pub const bidi_type_r: BidiType = @intCast(c.SBBidiTypeR);
/// `SBBidiTypeAL`, strong: right-to-left Arabic.
pub const bidi_type_al: BidiType = @intCast(c.SBBidiTypeAL);
/// Boundary neutral; continuation code units of multi-unit characters use this type.
pub const bidi_type_bn: BidiType = @intCast(c.SBBidiTypeBN);
/// `SBBidiTypeNSM`, weak: non-spacing mark.
pub const bidi_type_nsm: BidiType = @intCast(c.SBBidiTypeNSM);
/// `SBBidiTypeAN`, weak: Arabic number.
pub const bidi_type_an: BidiType = @intCast(c.SBBidiTypeAN);
/// `SBBidiTypeEN`, weak: European number.
pub const bidi_type_en: BidiType = @intCast(c.SBBidiTypeEN);
/// `SBBidiTypeET`, weak: European number terminator.
pub const bidi_type_et: BidiType = @intCast(c.SBBidiTypeET);
/// `SBBidiTypeES`, weak: European number separator.
pub const bidi_type_es: BidiType = @intCast(c.SBBidiTypeES);
/// `SBBidiTypeCS`, weak: common number separator.
pub const bidi_type_cs: BidiType = @intCast(c.SBBidiTypeCS);
/// `SBBidiTypeWS`, neutral: white space.
pub const bidi_type_ws: BidiType = @intCast(c.SBBidiTypeWS);
/// `SBBidiTypeS`, neutral: segment separator.
pub const bidi_type_s: BidiType = @intCast(c.SBBidiTypeS);
/// Paragraph separator; rule P1 ends a paragraph at the first one.
pub const bidi_type_b: BidiType = @intCast(c.SBBidiTypeB);
/// `SBBidiTypeON`, neutral: other neutral.
pub const bidi_type_on: BidiType = @intCast(c.SBBidiTypeON);
/// `SBBidiTypeLRI`, format: left-to-right isolate.
pub const bidi_type_lri: BidiType = @intCast(c.SBBidiTypeLRI);
/// `SBBidiTypeRLI`, format: right-to-left isolate.
pub const bidi_type_rli: BidiType = @intCast(c.SBBidiTypeRLI);
/// `SBBidiTypeFSI`, format: first strong isolate.
pub const bidi_type_fsi: BidiType = @intCast(c.SBBidiTypeFSI);
/// `SBBidiTypePDI`, format: pop directional isolate.
pub const bidi_type_pdi: BidiType = @intCast(c.SBBidiTypePDI);
/// `SBBidiTypeLRE`, format: left-to-right embedding.
pub const bidi_type_lre: BidiType = @intCast(c.SBBidiTypeLRE);
/// `SBBidiTypeRLE`, format: right-to-left embedding.
pub const bidi_type_rle: BidiType = @intCast(c.SBBidiTypeRLE);
/// `SBBidiTypeLRO`, format: left-to-right override.
pub const bidi_type_lro: BidiType = @intCast(c.SBBidiTypeLRO);
/// `SBBidiTypeRLO`, format: right-to-left override.
pub const bidi_type_rlo: BidiType = @intCast(c.SBBidiTypeRLO);
/// `SBBidiTypePDF`, format: pop directional formatting.
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

/// Returns the big-endian OpenType script tag; unknown scripts use `DFLT`, not zero.
/// `scriptUnicodeTag` uses `0` for scripts absent from its table.
pub fn scriptOpenTypeTag(script: Script) u32 {
    return c.SBScriptGetOpenTypeTag(script);
}

/// Facade errors for invalid inputs, missing allocator callbacks, and upstream allocation failure.
/// `Line.visualOrder` returns only `std.mem.Allocator.Error`.
pub const Error = error{
    /// Source has no code units; upstream rejects an empty sequence.
    EmptySource,
    /// Code-unit range exceeds its source; upstream would clamp it.
    RangeOutOfBounds,
    /// Code-unit range is empty where a paragraph or line is required.
    EmptyRange,
    /// Explicit base level exceeds `level_max`; upstream would treat it as automatic.
    InvalidBaseLevel,
    /// Upstream could not allocate an object; the C library owns that memory.
    OutOfMemory,
    /// Required `allocateBlock` or `deallocateBlock` callback is missing.
    /// Rejected before calling upstream or allocating an object.
    MissingProtocolFunction,
};

/// Explicit embedding level or automatic P2/P3 fallback.
/// Explicit values above `level_max` return `Error.InvalidBaseLevel`.
pub const BaseLevel = union(enum) {
    /// Rules P2 and P3 with a left-to-right fallback (`SBLevelDefaultLTR`).
    auto_ltr,
    /// Rules P2 and P3 with a right-to-left fallback (`SBLevelDefaultRTL`).
    auto_rtl,
    /// Explicit level through `level_max`; `level_max` triggers upstream's P2/P3 fallback.
    /// Larger values fail in `toC`.
    explicit: Level,

    /// Converts to upstream's level value; out-of-range explicit values return `Error.InvalidBaseLevel`.
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

/// Upstream encoding identifiers; UTF-16 and UTF-32 use native endianness.
pub const Encoding = enum(u32) {
    /// `SBStringEncodingUTF8`.
    utf8 = c.SBStringEncodingUTF8,
    /// `SBStringEncodingUTF16`, native endianness.
    utf16 = c.SBStringEncodingUTF16,
    /// `SBStringEncodingUTF32`, native endianness.
    utf32 = c.SBStringEncodingUTF32,
};

/// Borrowed source text; this union stores slices and never owns or copies them.
/// Keep code units alive and unchanged while any derived object or loaded locator uses them.
pub const Source = union(Encoding) {
    /// Code units of UTF-8. Borrowed; see the type's contract.
    utf8: []const u8,
    /// Code units of UTF-16 in native endianness. Borrowed; see the type's
    /// contract.
    utf16: []const u16,
    /// Code units of UTF-32 in native endianness. Borrowed; see the type's
    /// contract.
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

    /// Number of source code units, not Unicode code points.
    pub fn codeUnits(self: Source) CodeUnitIndex {
        return switch (self) {
            .utf8 => |units| units.len,
            .utf16 => |units| units.len,
            .utf32 => |units| units.len,
        };
    }

    /// Length of the borrowed buffer in bytes.
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

/// Decodes at a source code-unit index; out-of-range input returns `codepoint_invalid` unchanged.
pub fn codepointAt(source: Source, index: CodeUnitIndex) DecodedCodepoint {
    if (index >= source.codeUnits()) {
        return .{ .codepoint = codepoint_invalid, .next = index };
    }
    const sequence = source.sequence();
    var cursor = index;
    const cp = c.SBCodepointSequenceGetCodepointAt(&sequence, &cursor);
    return .{ .codepoint = cp, .next = cursor };
}

/// Decodes before an index; `index == source.codeUnits()` is valid.
/// Zero or out-of-range indices return `codepoint_invalid` without changing the index.
pub fn codepointBefore(source: Source, index: CodeUnitIndex) DecodedPreviousCodepoint {
    if (index == 0 or index > source.codeUnits()) {
        return .{ .codepoint = codepoint_invalid, .start = index };
    }
    const sequence = source.sequence();
    var cursor = index;
    const cp = c.SBCodepointSequenceGetCodepointBefore(&sequence, &cursor);
    return .{ .codepoint = cp, .start = cursor };
}

/// Decodes UTF-8 at `index`; out-of-range input returns `codepoint_invalid` without advancing.
pub fn codepointDecodeNextFromUtf8(units: []const u8, index: CodeUnitIndex) DecodedCodepoint {
    var cursor = index;
    const cp = c.SBCodepointDecodeNextFromUTF8(units.ptr, units.len, &cursor);
    return .{ .codepoint = cp, .next = cursor };
}

/// Decodes UTF-8 before `index`; `index == units.len` is valid.
/// Zero or out-of-range indices return `codepoint_invalid` unchanged.
pub fn codepointDecodePreviousFromUtf8(units: []const u8, index: CodeUnitIndex) DecodedPreviousCodepoint {
    var cursor = index;
    const cp = c.SBCodepointDecodePreviousFromUTF8(units.ptr, units.len, &cursor);
    return .{ .codepoint = cp, .start = cursor };
}

/// Decodes native-endian UTF-16 at `index`; out-of-range input returns `codepoint_invalid` unchanged.
pub fn codepointDecodeNextFromUtf16(units: []const u16, index: CodeUnitIndex) DecodedCodepoint {
    var cursor = index;
    const cp = c.SBCodepointDecodeNextFromUTF16(units.ptr, units.len, &cursor);
    return .{ .codepoint = cp, .next = cursor };
}

/// Decodes native-endian UTF-16 before `index`; `index == units.len` is valid.
/// Zero or out-of-range indices return `codepoint_invalid` unchanged.
pub fn codepointDecodePreviousFromUtf16(units: []const u16, index: CodeUnitIndex) DecodedPreviousCodepoint {
    var cursor = index;
    const cp = c.SBCodepointDecodePreviousFromUTF16(units.ptr, units.len, &cursor);
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

/// Reference-counted algorithm over borrowed source text.
/// The caller owns each handle and must keep source code units alive.
pub const Algorithm = struct {
    /// Upstream algorithm handle; do not replace it.
    ref: c.SBAlgorithmRef,
    /// Borrow record used by this object and its derived objects.
    source: Source,

    /// Creates one owned handle and borrows `source` until all derived objects are released.
    /// Returns `EmptySource` or `OutOfMemory`.
    pub fn create(source: Source) Error!Algorithm {
        if (source.codeUnits() == 0) return Error.EmptySource;
        const sequence = source.sequence();
        const ref = c.SBAlgorithmCreate(&sequence);
        return .{ .ref = ref orelse return Error.OutOfMemory, .source = source };
    }

    /// Returns a second owned handle to the same object; call `deinit` once for it.
    pub fn retain(self: Algorithm) Algorithm {
        return .{ .ref = c.SBAlgorithmRetain(self.ref), .source = self.source };
    }

    /// Releases one owned handle and invalidates `self`.
    pub fn deinit(self: *Algorithm) void {
        c.SBAlgorithmRelease(self.ref);
        self.* = undefined;
    }

    /// Returns one bidi type per code unit; continuation units are `BN`.
    /// This slice borrows the algorithm's storage.
    pub fn bidiTypes(self: Algorithm) []const BidiType {
        const ptr: [*]const BidiType = c.SBAlgorithmGetBidiTypesPtr(self.ref);
        return ptr[0..self.source.codeUnits()];
    }

    /// Applies rule P1 to a checked code-unit range; CRLF is one separator.
    /// Invalid ranges return `RangeOutOfBounds`; empty ranges return zero lengths.
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

    /// Creates one owned paragraph; it retains this algorithm but borrows source text.
    /// Returns `RangeOutOfBounds`, `EmptyRange`, `InvalidBaseLevel`, or `OutOfMemory`.
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

/// Reference-counted paragraph; it retains its algorithm but borrows source text.
pub const Paragraph = struct {
    /// Underlying `SBParagraphRef`; do not replace it.
    ref: c.SBParagraphRef,
    /// Borrow record for the paragraph's source code units.
    source: Source,

    /// Index of the first code unit of the paragraph in the source.
    pub fn offset(self: Paragraph) CodeUnitIndex {
        return c.SBParagraphGetOffset(self.ref);
    }

    /// Number of code units in the paragraph, including its separator.
    pub fn length(self: Paragraph) CodeUnitIndex {
        return c.SBParagraphGetLength(self.ref);
    }

    /// Resolved level; explicit values below `level_max` survive unchanged.
    /// Automatic modes and explicit `level_max` resolve through P2/P3.
    pub fn baseLevel(self: Paragraph) Level {
        return c.SBParagraphGetBaseLevel(self.ref);
    }

    /// Returns resolved levels in source order; X9-removed units carry paragraph level.
    /// This slice borrows paragraph storage.
    pub fn levels(self: Paragraph) []const Level {
        const ptr: [*]const Level = c.SBParagraphGetLevelsPtr(self.ref);
        return ptr[0..self.length()];
    }

    /// Returns a second owned handle to the same object; call `deinit` once for it.
    pub fn retain(self: Paragraph) Paragraph {
        return .{ .ref = c.SBParagraphRetain(self.ref), .source = self.source };
    }

    /// Releases one owned handle and invalidates `self`.
    pub fn deinit(self: *Paragraph) void {
        c.SBParagraphRelease(self.ref);
        self.* = undefined;
    }

    /// Creates one owned line; the paragraph must outlive it and retained line handles.
    /// Returns `RangeOutOfBounds`, `EmptyRange`, or `OutOfMemory`.
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

/// Reference-counted line with visual-order runs; it does not retain its paragraph.
/// Borrowed source code units must outlive the line and any loaded mirror locator.
pub const Line = struct {
    /// Underlying `SBLineRef`; do not replace it.
    ref: c.SBLineRef,
    /// Borrow record used by the line and by `MirrorLocator.loadLine`.
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

    /// Returns a line-owned slice of runs in visual order; it borrows line storage.
    /// Run offsets and lengths are absolute source code-unit indices.
    pub fn runs(self: Line) []const Run {
        const ptr: [*]const Run = c.SBLineGetRunsPtr(self.ref);
        return ptr[0..self.runCount()];
    }

    /// Returns a second owned handle to the same object; call `deinit` once for it.
    pub fn retain(self: Line) Line {
        return .{ .ref = c.SBLineRetain(self.ref), .source = self.source };
    }

    /// Releases one owned handle and invalidates `self`.
    pub fn deinit(self: *Line) void {
        c.SBLineRelease(self.ref);
        self.* = undefined;
    }

    /// Allocates the absolute source code-unit order using `allocator`; caller frees it there.
    /// Returns only `OutOfMemory`; the result survives line deinitialization.
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
    /// Resolved script; paired punctuation may inherit its enclosed text's script.
    script: Script,
};

/// Walks script runs over borrowed code units; retains no source or algorithm.
/// Keep the source alive until deinitializing or loading different text.
pub const ScriptLocator = struct {
    /// Upstream locator handle; do not replace it.
    ref: c.SBScriptLocatorRef,

    /// Creates an unloaded locator; caller owns the handle and must deinit it.
    /// Returns `OutOfMemory`.
    pub fn create() Error!ScriptLocator {
        const ref = c.SBScriptLocatorCreate();
        return .{ .ref = ref orelse return Error.OutOfMemory };
    }

    /// Returns a second owned handle; call `deinit` once for it.
    pub fn retain(self: ScriptLocator) ScriptLocator {
        return .{ .ref = c.SBScriptLocatorRetain(self.ref) };
    }

    /// Releases one owned handle and invalidates `self`.
    pub fn deinit(self: *ScriptLocator) void {
        c.SBScriptLocatorRelease(self.ref);
        self.* = undefined;
    }

    /// Loads borrowed source and rewinds; keep its code units alive until reload or deinit.
    /// Empty sources are accepted and produce no runs.
    pub fn load(self: ScriptLocator, source: Source) void {
        const sequence = source.sequence();
        c.SBScriptLocatorLoadCodepoints(self.ref, &sequence);
    }

    /// Returns the current run after `moveNext` succeeds.
    pub fn run(self: ScriptLocator) ScriptRun {
        // Upstream returns the locator's non-null embedded agent.
        const agent = c.SBScriptLocatorGetAgent(self.ref).*;
        return .{ .offset = agent.offset, .length = agent.length, .script = agent.script };
    }

    /// Advances to the next run, returning `false` at the end; then rewinds.
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
    /// Absolute code unit index of the code point in the source, and the index
    /// of its first code unit when it occupies more than one.
    index: CodeUnitIndex,
    /// The code point that was found.
    codepoint: Codepoint,
    /// Its mirrored counterpart.
    mirrored: Codepoint,
};

/// Walks mirrors in odd-level line runs and retains the loaded line.
/// The paragraph and borrowed source must outlive that line and locator.
pub const MirrorLocator = struct {
    /// Upstream locator handle; do not replace it.
    ref: c.SBMirrorLocatorRef,

    /// Creates an unloaded locator; caller owns the handle and must deinit it.
    /// Returns `OutOfMemory`.
    pub fn create() Error!MirrorLocator {
        const ref = c.SBMirrorLocatorCreate();
        return .{ .ref = ref orelse return Error.OutOfMemory };
    }

    /// Returns a second owned handle; call `deinit` once for it.
    pub fn retain(self: MirrorLocator) MirrorLocator {
        return .{ .ref = c.SBMirrorLocatorRetain(self.ref) };
    }

    /// Releases one owned handle and invalidates `self`.
    pub fn deinit(self: *MirrorLocator) void {
        c.SBMirrorLocatorRelease(self.ref);
        self.* = undefined;
    }

    /// Loads and retains `line`; its buffer satisfies upstream's pointer-identity check.
    /// No error is reported; the paragraph and source must remain alive.
    pub fn loadLine(self: MirrorLocator, line: Line) void {
        c.SBMirrorLocatorLoadLine(self.ref, line.ref, line.source.buffer());
    }

    /// Returns the current mirror after `moveNext` succeeds.
    pub fn mirror(self: MirrorLocator) Mirror {
        // Upstream returns the locator's non-null embedded agent.
        const agent = c.SBMirrorLocatorGetAgent(self.ref).*;
        return .{ .index = agent.index, .codepoint = agent.codepoint, .mirrored = agent.mirror };
    }

    /// Advances to the next mirror, returning `false` at the end; then rewinds.
    pub fn moveNext(self: MirrorLocator) bool {
        return c.SBMirrorLocatorMoveNext(self.ref) != 0;
    }

    /// Rewinds to the first mirror of the loaded line.
    pub fn reset(self: MirrorLocator) void {
        c.SBMirrorLocatorReset(self.ref);
    }
};

/// Reference-counted allocator handle; each `create` or `retain` needs one `deinit`.
/// The default setter does not retain it; keep it alive until its objects are released.
pub const Allocator = struct {
    /// Upstream allocator handle; do not replace it.
    ref: AllocatorRef,

    /// Creates one owned allocator handle; `info` remains caller-owned for callbacks.
    /// Returns `MissingProtocolFunction` or `OutOfMemory`.
    pub fn create(protocol: AllocatorProtocol, info: ?*anyopaque) Error!Allocator {
        if (protocol.allocateBlock == null or protocol.deallocateBlock == null) {
            return Error.MissingProtocolFunction;
        }
        const ref = c.SBAllocatorCreate(&protocol, info);
        return .{ .ref = ref orelse return Error.OutOfMemory };
    }

    /// Returns a second owned handle; call `deinit` once for it.
    /// The process-default setter does not change the reference count.
    pub fn retain(self: Allocator) Allocator {
        return .{ .ref = c.SBAllocatorRetain(self.ref) };
    }

    /// Releases one owned handle and invalidates `self`.
    /// Restore another default before releasing the installed allocator.
    pub fn deinit(self: *Allocator) void {
        c.SBAllocatorRelease(self.ref);
        self.* = undefined;
    }
};
