// SPDX-License-Identifier: Apache-2.0

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
//! ## Routes
//!
//! The supported import is the package module, `dep.module("sheenbidi")`, and
//! `sheenbidi.c` is the supported raw escape hatch for whatever below does not
//! name. The build registers the translated header under the graph name `c`
//! (`build.zig:211`) because this file binds it by that name; that name is
//! wiring rather than a second supported import, and the declarations under it
//! are the ones `sheenbidi.c` already re-exports. For a C caller the product
//! is `libSheenBidi.a` and `SheenBidi/*.h`, written by `zig build --prefix`;
//! `zig build -fsys=sheenbidi` links an installed SheenBidi instead of building
//! one, and in that mode both the translation and the archive come from that
//! installation rather than from this tree.
//!
//! ## Two configurations: linked and runtime-loaded
//!
//! This module is built in one of two shapes, and `runtime_loaded` says which
//! at comptime.
//!
//! *Linked* is the default. The C library is linked, `c` is the translated
//! header, and every call below is a direct call with no table and no check.
//! This is the configuration the C archive was built for, and it is what a
//! `-fsys=sheenbidi` consumer gets as well.
//!
//! *Runtime-loaded* is opt-in. The library is not linked; `c` is a dispatch
//! generated from the same translation step's output, and all fifty-one `SB_PUBLIC`
//! functions the twenty reachable public headers declare are resolved through
//! the platform loader when the caller calls
//!
//! ```zig
//! try sheenbidi.load(.{ .path = "/usr/lib/libSheenBidi.so" });
//! ```
//!
//! before using anything else. A call into a module that has not loaded stops
//! the program with a message naming the function, in every optimization mode.
//! That is a programming error rather than a recoverable condition: the table
//! does not exist yet, and there is no partial state to fall back on. The load
//! itself reports a missing file, a provider that does not export what the
//! header declares, a provider whose version string or code point tables or
//! `SBCodepointSequence` layout do not answer as this ABI, a request that cannot
//! be honoured because a different provider already won, or a reentrant call,
//! as errors rather than as a different library being loaded instead.
//!
//! The provider is reached, never guessed. `.path` names a file and `.system`
//! names a library for the platform loader; neither falls back to the other,
//! the module has no unload and no reset, and it keeps the handle and its own
//! copy of the request to the end of the process.
//!
//! Nothing about the *answers* changes between the two configurations. A
//! runtime-loaded build resolves the same translated declarations and calls the
//! same functions with the same arguments; the borrowed code units in
//! [the borrow contract](#the-borrow-contract) are the caller's in both, the
//! reference counts in [Reference lifetimes](#reference-lifetimes) are the
//! provider's in both, and the memory in [Allocations](#allocations) is the
//! provider's in both. What the runtime route adds is one acquire load and one
//! branch per call, and it removes the link.
//!
//! What a provider must be is stated in `runtime/library.zig`, next to the ABI
//! boundary — scalar widths, the five structs that cross by pointer, the
//! allocator protocol and the reference counts — and what is and is not checked
//! about it.
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
//! A `Source` is that rule made a type, and it is a plain value: it holds the
//! slice, it does not own it, and copying one copies the borrow record and
//! nothing else. `Algorithm`, `Paragraph` and `Line` each store that record,
//! so the code units stay where the caller put them. They must stay alive and
//! unmodified until the **last** object derived from them is gone — the last
//! `Algorithm`, `Paragraph`, `Line`, loaded `ScriptLocator` and loaded
//! `MirrorLocator` among them, in whatever order they were created. A derived
//! object that has already been deinitialised does not extend the obligation;
//! a locator that is still loaded does.
//!
//! `Line` carries the record for a reason beyond bookkeeping:
//! `SBMirrorLocatorLoadLine` only accepts a buffer that is pointer-identical to
//! the one the line was built from (`Source/API/SBMirrorLocator.c:56`), and
//! silently ignores anything else, so the facade takes the buffer from the
//! line rather than from a second argument the caller could get wrong.
//!
//! ## Reference lifetimes
//!
//! The reference-counted upstream types are reference-counted here too, and the
//! relationship between them is upstream's, not invented:
//!
//!   * `SBAlgorithmCreateParagraph` retains the algorithm
//!     (`Source/API/SBParagraph.c:658`), so a `Paragraph` stays usable after
//!     its `Algorithm` is deinitialised.
//!   * `SBParagraphCreateLine` does *not* retain the paragraph.
//!     `SBLineCreate` copies the code point sequence and nothing else
//!     (`Source/API/SBLine.c:279`; the only `ObjectRetain` in that file is
//!     `SBLineRetain` on the line itself, `:313`), so a `Line` must not
//!     outlive the `Paragraph` it came from.
//!   * `SBScriptLocatorLoadCodepoints` copies the sequence by value
//!     (`Source/API/SBScriptLocator.c:58`), which is another borrow and no
//!     retain.
//!   * `SBMirrorLocatorLoadLine` retains the line
//!     (`Source/API/SBMirrorLocator.c:57`), so a `MirrorLocator` outlives the
//!     handle it was given. It retains the *line object*, not the text: the
//!     code units remain the caller's obligation for as long as the locator is
//!     loaded.
//!
//! That count counts **handles**, not struct copies. `retain` increments it
//! and hands back a second handle the caller owns; `deinit` gives back exactly
//! one. Assigning one value to another (`var b = a;`) copies the same fields
//! without incrementing anything, so `deinit` on both copies returns two
//! references against one count. Every `create` and every `retain` therefore
//! owes exactly one `deinit`, on the handle it produced.
//!
//! ## Allocations
//!
//! `deinit` hands the object back to the upstream release function, which
//! frees it when its count reaches zero. That memory is the C library's and
//! not Zig's: `Algorithm`, `Paragraph`, `Line`, `ScriptLocator` and
//! `MirrorLocator` are allocated by SheenBidi and freed by SheenBidi, so
//! `std.testing`'s leak oracle does not see them and a leak in one is
//! invisible to the test framework.
//!
//! The one allocation this facade makes is `Line.visualOrder`, and that one
//! is the caller's: it comes from the allocator the caller passed and is
//! released by the caller through that same allocator.
//!
//! ### Redirecting the native allocator
//!
//! `SBAllocatorSetDefault` is a raw `c` route and it is **process-global**:
//! `Source/API/SBAllocator.c:31` is a `static` atomic pointer and the setter is
//! a bare store into it (`:276-279`). It reaches every thread and every object
//! in the process, including ones this facade never touched.
//!
//! What it actually controls, read out of the source:
//!
//!   * Every object block is allocated through `SBAllocatorAllocateBlock(NULL,
//!     …)` (`Source/Core/Memory.c:78`, `:95`), which resolves the *current*
//!     default at the moment of the call (`Source/API/SBAllocator.c:211-218`).
//!   * Every free goes through `SBAllocatorDeallocateBlock(NULL, block)`
//!     (`Source/Core/Memory.c:144`), which resolves the current default
//!     **again**, at the moment of the release
//!     (`Source/API/SBAllocator.c:229-236`).
//!   * No object and no memory block records the allocator it came from.
//!
//! That last point is the whole retention rule, and it is a correctness
//! requirement rather than a style preference: an object created while
//! allocator `A` was the default and released after the default became `B` is
//! freed through `B`. The default in force at creation must therefore still be
//! in force at the last release, for every object. Arbitrary swaps are safe
//! only while no object created under the previous default is still live, and
//! that is the whole of the safe authority to change it:
//!
//!   * Install once, before the first SheenBidi object of the process is
//!     created, and keep it installed until the last object created under it
//!     has been released. Restoring the previous default, or `NULL`, is
//!     itself a change and obeys the same rule.
//!   * The setter does not retain. It is an `AtomicPointerStore` and nothing
//!     more, so the caller keeps the allocator object alive and valid for as
//!     long as it is the default. `SBAllocatorRetain`
//!     (`Source/API/SBAllocator.c:297`) and `SBAllocatorRelease` (`:302`) are
//!     the upstream reference count; a process that installs the same allocator
//!     from more than one place has to count its own handles.
//!   * The allocator object is itself allocated through the default in force
//!     when it was created and freed through the default in force when its own
//!     count reaches zero (`SBAllocatorCreate` calls `ObjectCreate`,
//!     `Source/API/SBAllocator.c:287`), so it obeys the same rule as every
//!     other object.
//!
//! The protocol, as this implementation actually calls it: `allocateBlock` and
//! `deallocateBlock` are called unconditionally
//! (`Source/API/SBAllocator.c:217`, `:235`); `allocateScratch` and
//! `resetScratch` are called only when non-`NULL` (`:247-251`, `:264-268`), and
//! a scratch request that comes back `NULL` falls back to `allocateBlock`
//! (`Source/Core/Memory.c:68-72`) rather than failing; `reallocateBlock` is
//! called unconditionally where a `List` grows (`Source/Core/List.c:72`),
//! which in this build is reached only from the experimental text API that is
//! not compiled — see below. A member the implementation calls
//! unconditionally has to be non-`NULL`.
//!
//! Scratch memory is upstream's, not the caller's. Paragraph resolution and
//! line construction request `MemoryTypeScratch` (`Source/API/SBParagraph.c:66`,
//! `Source/API/SBLine.c:54`) and reset it before returning
//! (`SBParagraph.c:665`, `SBLine.c:286`), so `resetScratch` runs on the calling
//! thread only and a custom allocator that implements scratch has to make that
//! thread-local itself (`Headers/SheenBidi/SBAllocator.h:69-70`).
//!
//! `SBAllocatorGetDefault` returns the stored pointer, which is `NULL` when no
//! custom allocator is installed (`Source/API/SBAllocator.c:271-274`). The
//! built-in allocator used in that case is a `static` object (`:187-189`) that
//! none of these functions ever returns.
//!
//! What this facade adds is a typed owner for an allocator *object* — the one a
//! caller creates with `Allocator.create` and installs — plus a rejection of
//! the one thing upstream does not reject. `SBAllocatorCreate`
//! (`Source/API/SBAllocator.c:283-295`) copies the protocol by value and
//! returns whatever `ObjectCreate` allocated; it never looks at
//! `allocateBlock` or `deallocateBlock`, so a protocol missing either is
//! accepted there and then dereferences a null pointer on the first allocation
//! (`Source/Core/Memory.c:78`, `:144`). `Allocator.create` therefore requires
//! those two members and reports `Error.MissingProtocolFunction` without
//! calling upstream, which is the wrapper owning a bound upstream does not
//! hold. Nothing is allocated when it refuses.
//!
//! It does **not** wrap `SBAllocatorSetDefault`. A process-wide default has no
//! owner here, and a leak oracle for one would have to live outside the test
//! framework; installing and restoring it is two explicit raw calls, and the
//! rules above are the contract a caller takes on by making them. The raw
//! route stays reachable as `c.SBAllocatorSetDefault` and
//! `c.SBAllocatorGetDefault`, and `Allocator` is the same object either way,
//! because its handle is `c.SBAllocatorRef`.
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
//! upstream treats them very differently. `DetermineParagraphLevel`
//! (`Source/API/SBParagraph.c:256`) dispatches on `baseLevel >= SBLevelMax`:
//! at or above 125 it ignores the value except to pick the fallback and
//! resolves the paragraph through rules P2 and P3, and below 125 it uses the
//! value verbatim. The sentinels are therefore not levels at all, and
//! `.auto_ltr` / `.auto_rtl` name the only two of them this type admits.
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
//! of source indices, which is the form a renderer or a test wants. That
//! result is allocated from the caller's allocator through
//! `std.mem.Allocator.Error` — `error.OutOfMemory` is the whole error channel
//! of the method, because the allocation is the only thing in it that can
//! fail — it has exactly `line.length()` entries, and it is the caller's to
//! release through the allocator it passed.
//!
//! ## Experimental text API
//!
//! Upstream's text-editing API (`SBText`, `SBTextConfig`, `SBTextIterators`)
//! is compiled out by default: `Headers/SheenBidi/SBConfig.h:39` leaves
//! `SB_CONFIG_EXPERIMENTAL_TEXT_API` commented out, and `SBBase.h:44` keys
//! `SB_TEXT_API_SUPPORTED` off that macro. Nothing in this module reaches for
//! it, and no stub stands in for it. The fork builds upstream's default
//! configuration, so the symbols do not exist in the archive to stub. That is
//! also the only place a growing `List` would reach `reallocateBlock`
//! (`Source/Core/List.c:72`), so this configuration never calls it.
//!
//! ## Using it
//!
//! Reach the module as `dep.module("sheenbidi")`; the shortest sequence that
//! produces a visual order is this. The `defer`s release in the reverse of
//! the order the objects were made, and `text` has to outlive all three.
//!
//! ```zig
//! const std = @import("std");
//! const sheenbidi = @import("sheenbidi");
//!
//! pub fn main(init: std.process.Init) !void {
//!     const text = "car means \u{05D0}\u{05D1}\u{05D2}.";
//!     const source = sheenbidi.Source.fromUtf8(text);
//!     var algorithm = try sheenbidi.Algorithm.create(source);
//!     defer algorithm.deinit();
//!     var paragraph = try algorithm.createParagraph(0, source.codeUnits(), .auto_ltr);
//!     defer paragraph.deinit();
//!     var line = try paragraph.createLine(paragraph.offset(), paragraph.length());
//!     defer line.deinit();
//!     const order = try line.visualOrder(init.gpa);
//!     defer init.gpa.free(order);
//!     std.debug.print("{any}\n", .{order});
//! }
//! ```

const std = @import("std");

/// Every declaration transcribed from the upstream public headers, with `c`
/// bound to the translated aggregate header. This is the unmodified upstream
/// ABI: the whole stable surface stays reachable from here, including the
/// allocator protocol and the codepoint decoders this facade wraps.
///
/// It is a supported escape hatch, not a private detail, and it carries
/// upstream's own contracts rather than this facade's: nothing here re-checks
/// an argument, and a raw call that reaches past a facade method has none of
/// the bounds checks above it. The allocator protocol in particular is a
/// process-global setting with the retention rule stated under
/// [Allocations](#allocations); `c.SBAllocatorSetDefault` is the supported way
/// to install one and those rules are what taking it on means.
///
/// In a runtime-loading build this module is a generated dispatch instead of
/// the translation step's own output. It publishes the same namespace: every
/// type and constant is re-exported from the translated header rather than
/// restated, so `Run` is the same nominal type either way and nothing here
/// needs a cast. All fifty-one `SB_PUBLIC` functions are present as wrappers with
/// upstream's own signatures, so the escape hatch is as complete in that
/// configuration as in this one. What differs is how a name reaches the
/// library: in the linked configuration it is a direct call, and in the
/// runtime-loaded one it is a call through a table that `load` fills, with a
/// call before that fill stopping the program with a message naming the
/// function. `runtime_loaded` says which configuration this build is, at
/// comptime.
pub const c = @import("c");

/// `SBAllocatorRef`, `Headers/SheenBidi/SBAllocator.h:24`: an opaque,
/// reference-counted handle to an allocator object. It is `const struct
/// _SBAllocator *`, so the object behind it is not writable through the
/// handle; only the process-wide default pointer in `SBAllocatorSetDefault`
/// changes which object new allocations use.
pub const AllocatorRef = c.SBAllocatorRef;
/// `SBAllocatorProtocol`, `Headers/SheenBidi/SBAllocator.h:108-136`: the six
/// callbacks a custom allocator is made of. The translated struct, so a
/// protocol literal has the upstream field names and the upstream nullability:
/// `allocateBlock` and `deallocateBlock` are called unconditionally and must
/// be set, while `reallocateBlock`, `allocateScratch`, `resetScratch` and
/// `finalize` are each optional and fall back when absent.
pub const AllocatorProtocol = c.SBAllocatorProtocol;

/// The loader core, which is where a linked build's two public types come from.
///
/// It is imported only by the linked configuration. In a runtime-loading build
/// the dispatch carries its own copy of the same declarations, and this module
/// is never referenced, so it is never resolved and never compiled. Either way
/// there is exactly one `LoadSource` and one `LoadError` in a build, which is
/// what keeps them one type for a consumer that names them.
const rt = @import("rt");

/// Whether this module was configured to resolve its native symbols at run
/// time.
///
/// False for the ordinary build, where the C library is linked and `c` is the
/// translated header itself. True when the build generated a dispatch that
/// resolves the same symbols through the platform loader, in which case `load`
/// is the call that makes the library usable.
///
/// It is a comptime constant, so a consumer can write two different code paths
/// and have only the one it chose analyzed.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Which native library `load` should open.
///
/// `.path` is an explicit file path and `.system` is an explicit name for the
/// platform loader. There is no path-to-system fallback and no implicit
/// fallback of any kind; a request that cannot be honoured is an error, not a
/// different library.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Every way `load` can decline.
///
/// Declared here, in the module a consumer imports, rather than only inside the
/// loader: the caller names the failure it is handling.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Load the native library this module dispatches to.
///
/// In a runtime-loading build this is the whole contract: call it once, then
/// use this module as if it were linked. Calling it again with the same request
/// succeeds and changes nothing; calling it with a different request after a
/// success is `ProviderMismatch`, and the library already in use stays in use.
/// A failed attempt publishes nothing and can be retried explicitly, by
/// calling this again: there is no automatic retry, and no implicit second
/// source.
///
/// It keeps the process handle and its own copy of the request to the end of
/// the process. There is no unload and no reset, because the table is
/// process-global state that other code may already have called through.
///
/// Safe to call from any thread. A thread that arrives while an attempt for the
/// same request is in flight waits for that attempt and gets its result,
/// whatever it was. A call from the thread that is running the attempt is
/// `ReentrantLoad` rather than a deadlock.
///
/// In a linked build there is no provider, no table and nothing to resolve, so
/// this stops the program with a message saying so instead of quietly
/// succeeding. `runtime_loaded` is false there, so a consumer that supports
/// both configurations can tell the two apart at comptime instead of meeting
/// this at run time.
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

/// The request that succeeded, or null when nothing has loaded yet.
///
/// The answer is the loader's own retained copy and stays valid for the life of
/// the process. Null in a linked build, which has no request.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

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
/// The translated struct, so `offset`, `length` and `level` are ordinary
/// public fields a caller may write; one returned by `Line.runs` belongs to
/// the line's own storage, and writing into it corrupts a live line rather
/// than producing a local edit.
pub const Run = c.SBRun;
/// `SBUInteger`, `Headers/SheenBidi/SBBase.h:102`: an unsigned integer as wide
/// as a pointer. Every offset and length SheenBidi publishes is one of these,
/// and every index here counts code units, not code points.
pub const CodeUnitIndex = c.SBUInteger;

/// The version string of the linked C library (`SBVersionGetString`).
///
/// Sentinel-terminated and owned by the C library, so it is valid for as long
/// as the process has the library loaded and needs no release. Which release
/// that is belongs to the provenance gate; this call reports what the linked
/// archive actually is.
pub fn versionString() [:0]const u8 {
    return std.mem.span(c.SBVersionGetString());
}

// ---------------------------------------------------------------------------
// Header macros. An object-like `#define` reaches the translated `c` as a
// `pub const`, so each value below is read out of the header that declares it
// rather than written down here a second time.
// ---------------------------------------------------------------------------

/// `SBLevelInvalid`, `Headers/SheenBidi/SBBase.h:143`: the value an
/// unresolvable level reports as `0xFF`. It is not a level a paragraph can be
/// resolved against, and `BaseLevel` does not offer it.
pub const level_invalid: Level = @intCast(c.SBLevelInvalid);
/// `SBLevelMax`, `Headers/SheenBidi/SBBase.h:148`: the highest level an
/// explicit embedding can reach. Note that upstream's own base-level dispatch
/// treats this value as "not explicit" (`baseLevel >= SBLevelMax`), so
/// `BaseLevel.explicit` accepts it and `DetermineParagraphLevel` does not use
/// it verbatim.
pub const level_max: Level = @intCast(c.SBLevelMax);
/// `SBLevelDefaultLTR`, `Headers/SheenBidi/SBBase.h:153`: rule P2 and P3 with
/// a left-to-right fallback. What `.auto_ltr` passes upstream.
pub const level_default_ltr: Level = @intCast(c.SBLevelDefaultLTR);
/// `SBLevelDefaultRTL`, `Headers/SheenBidi/SBBase.h:158`: rule P2 and P3 with
/// a right-to-left fallback. What `.auto_rtl` passes upstream.
pub const level_default_rtl: Level = @intCast(c.SBLevelDefaultRTL);

/// `SBCodepointInvalid`, `Headers/SheenBidi/SBCodepoint.h:35`.
pub const codepoint_invalid: Codepoint = @intCast(c.SBCodepointInvalid);
/// `SBCodepointFaulty`, `Headers/SheenBidi/SBCodepoint.h:42`: what decoding
/// substitutes for a code point it cannot recognise.
pub const codepoint_faulty: Codepoint = @intCast(c.SBCodepointFaulty);
/// `SBCodepointMax`, `Headers/SheenBidi/SBCodepoint.h:49`.
pub const codepoint_max: Codepoint = @intCast(c.SBCodepointMax);

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

// The 24 members of the `SBBidiType` enum, `Headers/SheenBidi/SBBidiType.h:28-55`,
// read out of the translated constants rather than written down a second time.
// The other 23 partition into the four families the `bidiTypeIs*` predicates
// below test, and every per-code-unit table this module exposes uses those
// values. `Nil` is the twenty-fourth and belongs to none of the families: it is
// the library's own unset marker (`Source/UBA/BidiChain.c:32`,
// `Source/UBA/BracketQueue.c:165`), not a type a classified code unit is
// given.

/// `SBBidiTypeNil`, `0x00`: the library's unset marker. It is in none of the
/// four families, so a `bidiTypeIs*` predicate is `false` for it.
pub const bidi_type_nil: BidiType = @intCast(c.SBBidiTypeNil);
/// `SBBidiTypeL`, strong: left-to-right.
pub const bidi_type_l: BidiType = @intCast(c.SBBidiTypeL);
/// `SBBidiTypeR`, strong: right-to-left.
pub const bidi_type_r: BidiType = @intCast(c.SBBidiTypeR);
/// `SBBidiTypeAL`, strong: right-to-left Arabic.
pub const bidi_type_al: BidiType = @intCast(c.SBBidiTypeAL);
/// `SBBidiTypeBN`, weak: boundary neutral. Also the type given to every code
/// unit after the first of a multi-unit code point.
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
/// `SBBidiTypeB`, neutral: paragraph separator. Rule P1 ends a paragraph at
/// the first of these.
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

/// `SBScriptGetOpenTypeTag`, `Headers/SheenBidi/SBScript.h:274`: the OpenType
/// script tag as a big-endian `u32`.
///
/// It is never `0`. Every script the table at `Source/API/SBBase.c:94-468` does
/// not name — `SBScriptNil` among them, and `SBScriptZinh` and `SBScriptZyyy`
/// as well — answers `DFLT` at `:467-468`, so a caller that wants "no OpenType
/// script" compares against `DFLT` rather than against zero. Zero is what
/// `scriptUnicodeTag` answers instead, and only for the scripts its own table
/// (`:474-826`) does not name; that table names every script Unicode defines,
/// `Zinh` and `Zyyy` included, so the two functions answer differently for
/// those two and for `beng`, which is `bng2` here and `Beng` there. A caller
/// that assumes either can substitute for the other is wrong for those
/// scripts.
pub fn scriptOpenTypeTag(script: Script) u32 {
    return c.SBScriptGetOpenTypeTag(script);
}

// ---------------------------------------------------------------------------
// Errors. The set and each of its members carry the contract at the point of
// declaration, not here.
// ---------------------------------------------------------------------------

/// Every error this facade can report.
///
/// Each entry names one condition this package established itself. Upstream
/// has no error channel at all: it returns NULL. Because this module checks
/// the arguments before handing them over, the NULL that is left is upstream's
/// allocation failure and nothing else, and it is reported once as
/// `OutOfMemory` rather than given a name it cannot support. The set is the
/// five argument conditions below plus one the wrapper owns outright:
/// `MissingProtocolFunction`, which upstream never reports because upstream
/// never looks.
///
/// The one method outside it is `Line.visualOrder`, whose channel is
/// `std.mem.Allocator.Error` in full — the allocation is the only thing in it
/// that can fail.
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
    /// An explicit base level above `level_max` — that is, anything from `126`
    /// up, which is every remaining `SBLevel` value including all three
    /// sentinels. Upstream would read most of those as a default too, but a
    /// type that offered them would be offering upstream's dispatch rather
    /// than a base level.
    InvalidBaseLevel,
    /// SheenBidi could not allocate one of its objects. This is the only
    /// remaining reason the C returns NULL once the argument has been checked,
    /// and the memory involved is the C library's own, so a Zig leak oracle
    /// sees nothing on either side of this error.
    OutOfMemory,
    /// An allocator protocol with no `allocateBlock` or no `deallocateBlock`.
    /// Both are called unconditionally (`Source/API/SBAllocator.c:217`, `:235`)
    /// and `SBAllocatorCreate` accepts the protocol anyway — it copies the
    /// struct by value and never inspects it (`:283-295`) — so a caller that
    /// omitted one would get a null call on the first allocation or the first
    /// release. Nothing is allocated when this is reported.
    MissingProtocolFunction,
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
    /// An explicit level in `0...125`, which is every value upstream can
    /// distinguish from its sentinels.
    ///
    /// `0` through `124` are used verbatim: the paragraph is resolved against
    /// that level, with rules P2 and P3 skipped, and the level survives into
    /// `Paragraph.baseLevel`.
    ///
    /// `125` is `level_max`, and it is the one accepted value upstream does
    /// **not** take verbatim. `DetermineParagraphLevel`
    /// (`Source/API/SBParagraph.c:258`) reads `baseLevel >= SBLevelMax` as
    /// "apply P2 and P3" and uses the value only to pick the fallback, which
    /// for anything but `SBLevelDefaultRTL` is left-to-right. An explicit
    /// `125` therefore resolves exactly as `.auto_ltr` does — a
    /// right-to-left text comes back as level `1` and a text with no strong
    /// character as `0` — and never as an explicit level of `125`. That is
    /// upstream's dispatch, kept as it is rather than corrected here.
    ///
    /// Above `level_max` there is nothing left to hand upstream, which is what
    /// `Error.InvalidBaseLevel` is for.
    explicit: Level,

    /// The `SBLevel` this resolves to: the value handed upstream, which for an
    /// explicit `125` is `125` even though upstream then resolves the paragraph
    /// through P2 and P3. `Error.InvalidBaseLevel` for an explicit level
    /// outside `0...level_max`.
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
    /// `SBStringEncodingUTF8`.
    utf8 = c.SBStringEncodingUTF8,
    /// `SBStringEncodingUTF16`, native endianness.
    utf16 = c.SBStringEncodingUTF16,
    /// `SBStringEncodingUTF32`, native endianness.
    utf32 = c.SBStringEncodingUTF32,
};

/// Borrowed source text, in one of the three encodings `SBCodepointSequence`
/// understands.
///
/// This is a borrow record, not an owner. The union holds the slice and never
/// a copy of it, and nothing in this module frees, resizes or replaces it.
/// The code units must stay alive and unmodified for as long as *any* object
/// derived from this record is alive: an `Algorithm`, a `Paragraph`, a
/// `Line`, or a `ScriptLocator` or `MirrorLocator` that has been loaded and
/// not yet released or loaded again. Copying the record copies the borrow, so
/// a copy kept in another struct neither extends the obligation nor shortens
/// it.
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
/// the C. An out-of-range index yields `codepoint_invalid` and leaves the
/// index where it was, which is what
/// `Headers/SheenBidi/SBCodepointSequence.h:62-63` documents. A code point
/// the decoder cannot recognise comes back as `codepoint_faulty`, not as an
/// error. The index names a code unit, so an index inside a multi-unit code
/// point decodes from there rather than from its start.
pub fn codepointAt(source: Source, index: CodeUnitIndex) DecodedCodepoint {
    if (index >= source.codeUnits()) {
        return .{ .codepoint = codepoint_invalid, .next = index };
    }
    const sequence = source.sequence();
    var cursor = index;
    const cp = c.SBCodepointSequenceGetCodepointAt(&sequence, &cursor);
    return .{ .codepoint = cp, .next = cursor };
}

/// `SBCodepointSequenceGetCodepointBefore`, with the bounds check hoisted out
/// of the C. The index may equal the source length, which is how a caller asks
/// for the code point before the end; index `0` is out of range in the same
/// way an index past the end is, and both report `codepoint_invalid` with the
/// index unchanged.
pub fn codepointBefore(source: Source, index: CodeUnitIndex) DecodedPreviousCodepoint {
    if (index == 0 or index > source.codeUnits()) {
        return .{ .codepoint = codepoint_invalid, .start = index };
    }
    const sequence = source.sequence();
    var cursor = index;
    const cp = c.SBCodepointSequenceGetCodepointBefore(&sequence, &cursor);
    return .{ .codepoint = cp, .start = cursor };
}

/// The four direct decoders, `SBCodepointDecodeNextFromUTF8`,
/// `SBCodepointDecodePreviousFromUTF8`,
/// `SBCodepointDecodeNextFromUTF16` and
/// `SBCodepointDecodePreviousFromUTF16`
/// (`Headers/SheenBidi/SBCodepoint.h:131-180`).
///
/// `codepointAt` and `codepointBefore` above go through
/// `SBCodepointSequence` and take a `Source`, which is the form the rest of
/// this module uses because an algorithm, a paragraph and a line all read
/// through one. These four take the encoding-specific buffer directly instead,
/// for a caller that has bytes and no sequence: a UTF-8 scanner that has not
/// decided what the text is, or a caller that wants the raw walk with no
/// `SBCodepointSequence` in the way.
///
/// They report the same three outcomes the sequence form does, and for the same
/// reasons:
///
///   * an index at or past the length for `Next`, and an index of `0` or past
///     the length for `Previous`, is `codepoint_invalid` with the index
///     unchanged. Upstream reaches that by a wrapping unsigned subtraction in
///     the `Previous` case (`Source/API/SBCodepoint.c:283`, `:345`), which is
///     why the index cannot be `0` there;
///   * bytes that do not form a code point are `codepoint_faulty`, not an error,
///     and the index stops at the first byte that stopped the decode rather than
///     at the end of the intended sequence (`:257-269`, `:350-351`);
///   * a well-formed code point advances the index to the first code unit past
///     it, and a lone high surrogate in UTF-16 advances by one and reports
///     `codepoint_faulty` (`:326-335`).
pub fn codepointDecodeNextFromUtf8(units: []const u8, index: CodeUnitIndex) DecodedCodepoint {
    var cursor = index;
    const cp = c.SBCodepointDecodeNextFromUTF8(units.ptr, units.len, &cursor);
    return .{ .codepoint = cp, .next = cursor };
}

/// See the note above the four direct decoders. `index` names the code unit the
/// walk reads *before*, so it may equal `units.len`. Index `0` is out of range
/// in the same way an index past the end is: both report `codepoint_invalid`
/// with the index unchanged, because nothing precedes the first code unit.
pub fn codepointDecodePreviousFromUtf8(units: []const u8, index: CodeUnitIndex) DecodedPreviousCodepoint {
    var cursor = index;
    const cp = c.SBCodepointDecodePreviousFromUTF8(units.ptr, units.len, &cursor);
    return .{ .codepoint = cp, .start = cursor };
}

/// See the note above the four direct decoders. UTF-16 here is native-endian
/// code units, which is the only form `SBCodepointDecodeNextFromUTF16` reads;
/// there is no byte-order argument in the C signature.
pub fn codepointDecodeNextFromUtf16(units: []const u16, index: CodeUnitIndex) DecodedCodepoint {
    var cursor = index;
    const cp = c.SBCodepointDecodeNextFromUTF16(units.ptr, units.len, &cursor);
    return .{ .codepoint = cp, .next = cursor };
}

/// See the note above the four direct decoders. `index` names the code unit the
/// walk reads *before*, so it may equal `units.len`. Index `0` is out of range
/// in the same way an index past the end is: both report `codepoint_invalid`
/// with the index unchanged, because nothing precedes the first code unit.
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

/// A SheenBidi algorithm object over one borrowed `Source`.
///
/// One reference-counted handle, created by `create` and given back by
/// `deinit`. The object lives in SheenBidi's own allocator and keeps no
/// record of it, so read the module's [Allocations](#allocations) section
/// before redirecting that allocator.
pub const Algorithm = struct {
    /// The upstream handle, `SBAlgorithmRef`. A public field in Zig, so it is
    /// writable and reachable: assigning to it detaches this struct from the
    /// object it names, and a `deinit` afterwards releases whatever the new
    /// value is. Treat it as the handle it is.
    ref: c.SBAlgorithmRef,
    /// The borrow this object reads through. Kept so that everything derived
    /// from it can name the same buffer, which `SBMirrorLocatorLoadLine`
    /// requires. It is the record, not the text: see `Source`.
    source: Source,

    /// Creates an algorithm over `source`, with one reference the caller owns
    /// and owes one `deinit`.
    ///
    /// The code units of `source` are borrowed, not copied, and must stay
    /// alive until this handle is deinitialised and every object derived from
    /// it is too.
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

    /// Increments the reference count and returns a second handle to the same
    /// object, which the caller owns and owes one `deinit`.
    ///
    /// This is how a second owner is created. A plain assignment
    /// (`var b = self;`) copies the two fields and increments nothing, so two
    /// `deinit` calls on the two copies would return two references against
    /// one count.
    pub fn retain(self: Algorithm) Algorithm {
        return .{ .ref = c.SBAlgorithmRetain(self.ref), .source = self.source };
    }

    /// Decrements the reference count, releasing the object at zero. One call
    /// per `create` and per `retain`, and no more: after it this value is
    /// `undefined`, and a second call on the same variable reads a handle
    /// that is no longer there.
    pub fn deinit(self: *Algorithm) void {
        c.SBAlgorithmRelease(self.ref);
        self.* = undefined;
    }

    /// The bidirectional type of every code unit of the source.
    ///
    /// This is a view into the algorithm's own storage, not a copy, and it has
    /// one entry per code unit: a multi-byte code point is followed by `BN`
    /// entries for the rest of its code units. It borrows the object, so it is
    /// valid until every handle to that object has been deinitialised; it is
    /// not affected by the borrowed code units going out of scope, but reading
    /// the text through it afterwards is.
    pub fn bidiTypes(self: Algorithm) []const BidiType {
        const ptr: [*]const BidiType = c.SBAlgorithmGetBidiTypesPtr(self.ref);
        return ptr[0..self.source.codeUnits()];
    }

    /// Applies rule P1 to find the end of the first paragraph in
    /// `[offset, offset + suggested)`, given in code units.
    ///
    /// A CR followed by LF counts as one separator, so the boundary lands after
    /// the LF (`Source/API/SBCodepointSequence.c:52-58`). A range that fits the
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
    /// code units, with one reference the caller owns and owes one `deinit`.
    ///
    /// The paragraph retains this algorithm internally
    /// (`Source/API/SBParagraph.c:658`), so it stays usable after `deinit` is
    /// called here — and that retain covers the *algorithm*, not the borrowed
    /// code units, which the paragraph goes on reading.
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
///
/// One reference-counted handle. It retains the `Algorithm` it was created
/// from, so it outlives that handle; it borrows the same code units, so it does
/// not outlive them.
pub const Paragraph = struct {
    /// The upstream handle, `SBParagraphRef`. A public field in Zig, so it is
    /// writable and reachable: assigning to it detaches this struct from the
    /// object it names. Treat it as the handle it is.
    ref: c.SBParagraphRef,
    /// The borrow the paragraph reads through. The record, not the text: see
    /// `Source`.
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
    /// sentinel that was passed in; for `.{ .explicit = n }` with `n <= 124`
    /// it is `n` unchanged, and for `.{ .explicit = 125 }` it is whatever P2
    /// and P3 resolved, which is the same thing `.auto_ltr` would have given.
    pub fn baseLevel(self: Paragraph) Level {
        return c.SBParagraphGetBaseLevel(self.ref);
    }

    /// The resolved embedding level of every code unit, in source order.
    ///
    /// A view into the paragraph's own storage, valid until every handle to
    /// that paragraph has been deinitialised. Code units that rule X9 removes
    /// are present and carry the paragraph level, which is what rule L1 does to
    /// them (`Source/API/SBLine.c:136`, `ResetLevels`).
    pub fn levels(self: Paragraph) []const Level {
        const ptr: [*]const Level = c.SBParagraphGetLevelsPtr(self.ref);
        return ptr[0..self.length()];
    }

    /// Increments the reference count and returns a second handle to the same
    /// object, which the caller owns and owes one `deinit`. A plain assignment
    /// (`var b = self;`) copies the two fields and increments nothing, so two
    /// `deinit` calls on the two copies would return two references against
    /// one count.
    pub fn retain(self: Paragraph) Paragraph {
        return .{ .ref = c.SBParagraphRetain(self.ref), .source = self.source };
    }

    /// Decrements the reference count, releasing the object at zero. One call
    /// per handle this caller owns, and no more: after it this value is
    /// `undefined`, and a second call on the same variable reads a handle
    /// that is no longer there.
    pub fn deinit(self: *Paragraph) void {
        c.SBParagraphRelease(self.ref);
        self.* = undefined;
    }

    /// Creates the line covering `[line_offset, line_offset + line_length)`,
    /// given in source code units, with one reference the caller owns and owes
    /// one `deinit`.
    ///
    /// The line does **not** retain the paragraph — `SBLineCreate` copies the
    /// code point sequence and nothing else
    /// (`Source/API/SBLine.c:279`) — so the paragraph must outlive every line
    /// made from it, including one held through `MirrorLocator`, which
    /// retains the line and inherits this rule.
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
///
/// One reference-counted handle. It does not retain the `Paragraph` it came
/// from, and it keeps reading the borrowed code units after that paragraph is
/// gone, so both must outlive the line.
pub const Line = struct {
    /// The upstream handle, `SBLineRef`. A public field in Zig, so it is
    /// writable and reachable: assigning to it detaches this struct from the
    /// object it names. Treat it as the handle it is.
    ref: c.SBLineRef,
    /// The borrow the line reads through, and the buffer
    /// `MirrorLocator.loadLine` hands upstream. The record, not the text: see
    /// `Source`.
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
    /// into the line's own storage. It borrows the line, so it is valid until
    /// every handle to that line has been given back — and a loaded
    /// `MirrorLocator` holds one of those, so the view dies with that locator
    /// when it is deinitialised or loaded again.
    ///
    /// Rule L2 permutes this array but never reverses a run, so a run at an
    /// odd level is drawn from `offset + length - 1` down to `offset`.
    /// `visualOrder` is the form that has already applied that.
    pub fn runs(self: Line) []const Run {
        const ptr: [*]const Run = c.SBLineGetRunsPtr(self.ref);
        return ptr[0..self.runCount()];
    }

    /// Increments the reference count and returns a second handle to the same
    /// object, which the caller owns and owes one `deinit`. A plain assignment
    /// (`var b = self;`) copies the two fields and increments nothing, so two
    /// `deinit` calls on the two copies would return two references against
    /// one count.
    pub fn retain(self: Line) Line {
        return .{ .ref = c.SBLineRetain(self.ref), .source = self.source };
    }

    /// Decrements the reference count, releasing the object at zero. One call
    /// per handle this caller owns, and no more: after it this value is
    /// `undefined`, and a second call on the same variable reads a handle
    /// that is no longer there.
    pub fn deinit(self: *Line) void {
        c.SBLineRelease(self.ref);
        self.* = undefined;
    }

    /// The code units of the line in the order they are drawn, left to right.
    ///
    /// This expands the visual run order into an explicit permutation of source
    /// indices: an even-level run contributes its code units forwards, an
    /// odd-level run backwards. The entries are **absolute source code unit
    /// indices**, so a renderer reads `source[offset .. offset + width]` for
    /// each one; the permutation is not a sequence of run numbers.
    ///
    /// The result is the only thing this module allocates. It has exactly
    /// `line.length()` entries, it comes from `allocator`, and it is released
    /// by calling `allocator.free` on it — the same allocator, not one
    /// substituted later. Nothing else here holds a reference to it: it stays
    /// valid after the line is deinitialised, and outliving the borrowed code
    /// units does not make its indices meaningful.
    ///
    /// The error channel is `std.mem.Allocator.Error` in full, which is
    /// `error.OutOfMemory` and nothing else: the allocation is the only step
    /// in this method that can fail, and no partial result is produced when it
    /// does.
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
/// (`Source/API/SBScriptLocator.c:58`) and retains nothing, so the code units
/// it was loaded with must stay alive and unmodified until it is deinitialised
/// or loaded again. Nothing about this locator retains an `Algorithm` or a
/// `Paragraph`: it is a second, independent reader of the same text.
pub const ScriptLocator = struct {
    /// The upstream handle, `SBScriptLocatorRef`. A public field in Zig, so it
    /// is writable and reachable: assigning to it detaches this struct from
    /// the object it names. Treat it as the handle it is.
    ref: c.SBScriptLocatorRef,

    /// Creates a locator with nothing loaded, with one reference the caller
    /// owns and owes one `deinit`. Reading runs before a `load` is not
    /// meaningful; a fresh locator reports no runs.
    pub fn create() Error!ScriptLocator {
        const ref = c.SBScriptLocatorCreate();
        return .{ .ref = ref orelse return Error.OutOfMemory };
    }

    /// Increments the reference count and returns a second handle to the same
    /// object, which the caller owns and owes one `deinit`. A plain assignment
    /// (`var b = self;`) copies the field and increments nothing, so two
    /// `deinit` calls on the two copies would return two references against
    /// one count.
    pub fn retain(self: ScriptLocator) ScriptLocator {
        return .{ .ref = c.SBScriptLocatorRetain(self.ref) };
    }

    /// Decrements the reference count, releasing the object at zero. One call
    /// per handle this caller owns, and no more: after it this value is
    /// `undefined`, and a second call on the same variable reads a handle
    /// that is no longer there.
    pub fn deinit(self: *ScriptLocator) void {
        c.SBScriptLocatorRelease(self.ref);
        self.* = undefined;
    }

    /// Loads `source` and rewinds to its first run.
    ///
    /// Loading is a borrow, not a copy: the code units must stay alive and
    /// unmodified until the locator is deinitialised or loaded again. Loading
    /// a second source releases nothing, because nothing was retained; it
    /// simply replaces the sequence the walk reads. An empty source is
    /// accepted here, unlike `Algorithm.create`, because upstream's locator has
    /// no length check of its own and simply reports no runs.
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
    /// Absolute code unit index of the code point in the source, and the index
    /// of its first code unit when it occupies more than one.
    index: CodeUnitIndex,
    /// The code point that was found.
    codepoint: Codepoint,
    /// Its mirrored counterpart.
    mirrored: Codepoint,
};

/// Walks the mirrored code points of a line.
///
/// Only runs at an odd level are considered: a mirror is applied where the
/// character is drawn right-to-left (`Source/API/SBMirrorLocator.c:78`).
///
/// The locator retains the line it is given
/// (`Source/API/SBMirrorLocator.c:57`), so it outlives that handle — but the
/// retain is on the line object only. The line does not retain its paragraph,
/// and neither the line nor the locator owns the borrowed code units, so the
/// paragraph and the text must both outlive a loaded locator.
pub const MirrorLocator = struct {
    /// The upstream handle, `SBMirrorLocatorRef`. A public field in Zig, so it
    /// is writable and reachable: assigning to it detaches this struct from
    /// the object it names. Treat it as the handle it is.
    ref: c.SBMirrorLocatorRef,

    /// Creates a locator with nothing loaded, with one reference the caller
    /// owns and owes one `deinit`. Reading mirrors before a `loadLine` is not
    /// meaningful; a fresh locator reports none.
    pub fn create() Error!MirrorLocator {
        const ref = c.SBMirrorLocatorCreate();
        return .{ .ref = ref orelse return Error.OutOfMemory };
    }

    /// Increments the reference count and returns a second handle to the same
    /// object, which the caller owns and owes one `deinit`. A plain assignment
    /// (`var b = self;`) copies the field and increments nothing, so two
    /// `deinit` calls on the two copies would return two references against
    /// one count.
    pub fn retain(self: MirrorLocator) MirrorLocator {
        return .{ .ref = c.SBMirrorLocatorRetain(self.ref) };
    }

    /// Decrements the reference count, releasing the object at zero. One call
    /// per handle this caller owns, and no more: after it this value is
    /// `undefined`, and a second call on the same variable reads a handle
    /// that is no longer there.
    pub fn deinit(self: *MirrorLocator) void {
        c.SBMirrorLocatorRelease(self.ref);
        self.* = undefined;
    }

    /// Loads `line` and rewinds to its first mirror.
    ///
    /// The buffer comes from `line` itself, not from a second argument.
    /// Upstream ignores a load whose buffer is not pointer-identical to the one
    /// the line was built from (`Source/API/SBMirrorLocator.c:56`), and an
    /// ignored load looks exactly like a line with no mirrors — so there is no
    /// error to report and nothing downstream can tell the two apart.
    ///
    /// This is what gives the locator its own reference to the line, and that
    /// reference is given back by the next `loadLine`
    /// (`Source/API/SBMirrorLocator.c:52`) or by `deinit`, which reaches
    /// `FinalizeMirrorLocator` (`:30`) when the locator's own count hits zero.
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

// ---------------------------------------------------------------------------
// The allocator object. Installing it is a raw call; owning one is not.
// ---------------------------------------------------------------------------

/// One reference-counted handle to an allocator object, as
/// `SBAllocatorCreate` produces it.
///
/// This is the object a caller builds a `SBAllocatorProtocol` for and installs
/// with `c.SBAllocatorSetDefault`. What this type adds is the reference
/// discipline that `SBAllocatorRetain`/`SBAllocatorRelease` provide and that a
/// plain `SBAllocatorRef` in a struct field does not: `create` and `retain` each
/// owe exactly one `deinit`, and a `deinit` gives back exactly one.
///
/// Creating one says nothing about whether it is installed. It is not the
/// default until `c.SBAllocatorSetDefault` is called with this handle, and
/// [the retention rule under Allocations](#allocations) applies from the moment
/// it is: an object created while allocator `A` was the default and released
/// after the default became `B` is freed through `B`, so the handle must stay
/// alive and the default in force until the last release.
///
/// The memory behind the object is SheenBidi's own — the allocator object is
/// itself allocated through the default in force when it was created
/// (`SBAllocatorCreate` calls `ObjectCreate`,
/// `Source/API/SBAllocator.c:287`) — so `std.testing`'s leak oracle sees
/// nothing on either side of a `deinit`.
pub const Allocator = struct {
    /// The upstream handle, `SBAllocatorRef`. A public field in Zig, so it is
    /// writable and reachable: assigning to it detaches this struct from the
    /// object it names, and a `deinit` afterwards releases whatever the new
    /// value is. Treat it as the handle it is.
    ref: AllocatorRef,

    /// Creates an allocator object from `protocol`, carrying `info` to every
    /// callback that takes a context, with one reference the caller owns and
    /// owes one `deinit`.
    ///
    /// `Error.MissingProtocolFunction` when `protocol.allocateBlock` or
    /// `protocol.deallocateBlock` is null. Upstream accepts either: it copies
    /// the protocol by value and never inspects it
    /// (`Source/API/SBAllocator.c:283-295`), and both members are then called
    /// unconditionally (`:217`, `:235`), so the omission would surface as a
    /// null call inside the library. Nothing has been allocated when this is
    /// reported. `Error.OutOfMemory` if `ObjectCreate` fails.
    ///
    /// The four optional members are left exactly as the caller left them:
    /// upstream falls back for a missing `reallocateBlock` or scratch pair and
    /// never calls a missing `finalize`, so a null there is upstream's
    /// documented behaviour rather than a defect, and this module does not
    /// invent a default for one.
    pub fn create(protocol: AllocatorProtocol, info: ?*anyopaque) Error!Allocator {
        if (protocol.allocateBlock == null or protocol.deallocateBlock == null) {
            return Error.MissingProtocolFunction;
        }
        const ref = c.SBAllocatorCreate(&protocol, info);
        return .{ .ref = ref orelse return Error.OutOfMemory };
    }

    /// Increments the reference count and returns a second handle to the same
    /// object, which the caller owns and owes one `deinit`. A plain assignment
    /// (`var b = self;`) copies the field and increments nothing, so two
    /// `deinit` calls on the two copies would return two references against
    /// one count.
    ///
    /// This is the count `SBAllocatorSetDefault` does *not* touch. The setter
    /// is a bare atomic store (`Source/API/SBAllocator.c:277-279`), so a
    /// process that installs one allocator from two places counts its own
    /// handles.
    pub fn retain(self: Allocator) Allocator {
        return .{ .ref = c.SBAllocatorRetain(self.ref) };
    }

    /// Decrements the reference count, releasing the object at zero and calling
    /// its `finalize` member with `info` if it has one
    /// (`Source/API/SBAllocator.c:191-197`). One call per handle this caller
    /// owns, and no more: after it this value is `undefined`, and a second call
    /// on the same variable reads a handle that is no longer there.
    ///
    /// A release while this object is still the process default frees it out
    /// from under every later allocation. The rule is the one in
    /// [Allocations](#allocations): restore the previous default first, or hold
    /// the handle until the default is no longer this object.
    pub fn deinit(self: *Allocator) void {
        c.SBAllocatorRelease(self.ref);
        self.* = undefined;
    }
};
