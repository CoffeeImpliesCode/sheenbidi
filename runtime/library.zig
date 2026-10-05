// SPDX-License-Identifier: Apache-2.0
//
//! SheenBidi's side of the runtime loader: the names its synchronization binding
//! has, and what it requires of a provider beyond resolving its symbols.
//!
//! Everything else about the runtime route is generic. `runtime/loader.zig` is
//! the state machine and the platform layer; `runtime/generate.zig` builds the
//! dispatch from whatever the translation step actually produced; `runtime/graph.zig`
//! wires them together. This file is what makes them SheenBidi's, and it is the
//! file another SDK replaces.
//!
//! ## What a provider must be
//!
//! All fifty-one functions the stable public surface declares, every one of
//! them. They are the `SB_PUBLIC` declarations of the headers `zig/translate.h`
//! reaches in this configuration:
//!
//!   * `SBAllocator.h:141-181` — `SBAllocatorGetDefault`,
//!     `SBAllocatorSetDefault`, `SBAllocatorCreate`, `SBAllocatorRetain`,
//!     `SBAllocatorRelease`;
//!   * `SBAlgorithm.h:38-119` — `SBAlgorithmCreate`,
//!     `SBAlgorithmGetBidiTypesPtr`, `SBAlgorithmGetParagraphBoundary`,
//!     `SBAlgorithmCreateParagraph`, `SBAlgorithmRetain`, `SBAlgorithmRelease`;
//!   * `SBCodepoint.h:86-180` — `SBCodepointGetBidiType`,
//!     `SBCodepointGetGeneralCategory`, `SBCodepointGetMirror`,
//!     `SBCodepointGetScript`, and the four `SBCodepointDecode*FromUTF8`/`UTF16`
//!     entry points;
//!   * `SBCodepointSequence.h:50-66` — `SBCodepointSequenceGetCodepointBefore`,
//!     `SBCodepointSequenceGetCodepointAt`;
//!   * `SBLine.h:35-84` — the six line accessors and lifetime calls;
//!   * `SBMirrorLocator.h:43-104` — the seven mirror-locator calls;
//!   * `SBParagraph.h:35-101` — the seven paragraph accessors and lifetime calls;
//!   * `SBScript.h:274-291` — `SBScriptGetOpenTypeTag`,
//!     `SBScriptGetUnicodeTag`;
//!   * `SBScriptLocator.h:43-102` — the seven script-locator calls;
//!   * `SBVersion.h:37` — `SBVersionGetString`.
//!
//! None of these is optional and none is excluded. There is no configuration
//! switch upstream that removes one of them: the only macro that gates a public
//! declaration is `SB_CONFIG_EXPERIMENTAL_TEXT_API` (`SBBase.h:44-48`), and this
//! build leaves it undefined, so the seven headers behind that guard
//! (`SBText.h`, `SBTextConfig.h`, `SBTextIterators.h`, `SBTextType.h`,
//! `SBAttributeInfo.h`, `SBAttributeList.h`, `SBAttributeRegistry.h`) expand to
//! nothing and declare nothing. Their absence is not a runtime-optional set; it
//! is a configuration in which they do not exist, on both sides of the boundary.
//!
//! The provider exports **no data**. Every stable public name is a function, and
//! the two tables that back the code point queries are internal
//! (`Source/Data/`), reached only through the functions above.
//!
//! ## The ABI boundary, stated honestly
//!
//! Four things have to agree between this build's translated header and the
//! provider, and only the first three are visible from the headers:
//!
//!   * **Scalar widths.** `SBUInteger` is `uintptr_t` and `SBInteger` is
//!     `intptr_t` (`SBBase.h:97-102`), so every offset, length and index crosses
//!     the boundary at the machine-word width of the *target*, not of the
//!     provider's build host. `SBLLevel`/`SBBidiType`/`SBScript`/
//!     `SBGeneralCategory` are all `SBUInt8`. A provider built for a
//!     32-bit target and loaded into a 64-bit one cannot work, and nothing in
//!     the loader can discover that.
//!   * **Struct layout by pointer.** `SBCodepointSequence`
//!     (`SBCodepointSequence.h:32-36`), `SBAllocatorProtocol`
//!     (`SBAllocator.h:108-136`), `SBRun` (`SBRun.h:28-32`),
//!     `SBScriptAgent` (`SBScriptLocator.h:31-35`) and `SBMirrorAgent`
//!     (`SBMirrorLocator.h:31-36`) are all passed or returned across the
//!     boundary by pointer, and their field order and padding are part of the
//!     contract. None of them has a configurable field, so a provider built from
//!     any revision of these headers at this pin agrees with them.
//!   * **The allocator protocol callbacks.** `SBAllocatorProtocol`
//!     (`SBAllocator.h:108-136`) is six function pointers with C signatures
//!     fixed by the header: `SBUInteger` sizes and `void *` context. Every
//!     object block the provider allocates and frees goes through whatever the
//!     process default is at the moment of the call
//!     (`Source/Core/Memory.c:78`, `:95`, `:144`), so a caller that installs a
//!     custom default must keep it in force for every object it created under
//!     it. That rule belongs to the facade, which documents it; the requirement
//!     here is only that the six pointers have the layout the header declares.
//!   * **Reference counting.** `SBAlgorithmRef`, `SBParagraphRef`,
//!     `SBLineRef`, `SBScriptLocatorRef`, `SBMirrorLocatorRef` and
//!     `SBAllocatorRef` are opaque `const struct _SBA* *` handles to objects
//!     the provider owns. Retain/release must be a real count: the facade hands
//!     out one handle per `create` and per `retain`, and the mirror locator's
//!     retain of a line (`Source/API/SBMirrorLocator.c:57`) and the paragraph's
//!     retain of its algorithm (`Source/API/SBParagraph.c:658`) are what the
//!     lifetime rules above rest on.
//!
//! What is **not** a requirement: which Unicode revision the provider's data
//! tables were built from. Nothing in the headers selects one, and
//! `Source/Data/` carries the tables as compiled-in arrays; two providers that
//! agree on the four points above can still disagree about a code point
//! introduced after the older one was built. The conformance fixtures in
//! `Tools/Unicode/` bound this package's own answer, not a provider's.
//!
//! ## What is checked at load time, and what is not
//!
//! `validate` runs after every symbol resolved and before anything is published.
//! It makes three observations, each of which is a property of the ABI rather
//! than of one Unicode revision:
//!
//!   1. `SBVersionGetString()` answers a NUL-terminated string that is neither
//!      empty nor unbounded. That is a check that the entry point behaves as a
//!      pointer-returning function of this ABI.
//!   2. `SBCodepointGetBidiType('A')` is `SBBidiTypeL` and
//!      `SBCodepointGetScript(U+05D0)` is `SBScriptHEBR`. Both code points have
//!      had those values in every Unicode revision SheenBidi has shipped, so a
//!      disagreement means the provider is not this library rather than that it
//!      is a different revision of it.
//!   3. `SBAlgorithmCreate` accepts an `SBCodepointSequence` this build laid out
//!      itself, and the object it returns is real enough to release. This is the
//!      check that would catch a provider whose struct layout differs.
//!
//! Each is a *check*, not proof. Resolving fifty-one symbols proves the file is
//! a SheenBidi of some build; it does not prove the pointer widths, the layout
//! of a struct this build never passed, or the Unicode revision agree. The
//! loader trusts native code, and so does this file: nothing here walks a type
//! the provider declared, because the provider declares no types.

const rt = @import("rt");

/// The synchronization this loader calls, bound by exact name.
///
/// The names below are `runtime/sync.h` compiled with
/// `RT_SYNC_PREFIX=sheenbidi_rt`, which is what `runtime/graph.zig` passes. Two
/// spellings of that prefix have to agree: this file names the symbols, and
/// graph.zig defines the macro. A build where they disagree does not link, and
/// that is the whole error report: there is no runtime path that could hide it.
///
/// The prefix is `sheenbidi_rt` and nothing else. SheenBidi's own exports all
/// begin `SB`, so there is no collision with the library's namespace; the
/// prefix only has to be distinct from the other SDKs that might be loaded into
/// one process.
///
/// The core in `runtime/loader.zig` never names a symbol of its own, which is
/// what lets two SDKs, or two configurations of one SDK, hold their own loader
/// state in one process without sharing any of it.
pub const Sync = struct {
    extern fn sheenbidi_rt_lock() void;
    extern fn sheenbidi_rt_unlock() void;
    extern fn sheenbidi_rt_wait() void;
    extern fn sheenbidi_rt_broadcast() void;
    // `unsigned long long`. Declared as u64, which is the same type in every
    // ABI this SDK targets: 64-bit on x86_64, aarch64, riscv64 and wasm32.
    extern fn sheenbidi_rt_thread_self() u64;

    pub fn lock() void {
        sheenbidi_rt_lock();
    }
    pub fn unlock() void {
        sheenbidi_rt_unlock();
    }
    pub fn wait() void {
        sheenbidi_rt_wait();
    }
    pub fn broadcast() void {
        sheenbidi_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return sheenbidi_rt_thread_self();
    }
};

/// The longest version string `validate` will read before giving up.
///
/// `SBVersionGetString` returns a `const char *` the provider owns, and reading
/// it means walking it to its terminator. A provider is trusted native code, but
/// a walk with no ceiling turns a wrong pointer into an unbounded read rather
/// than a refusal, and every version string upstream has published fits in
/// three lines.
const max_version_len = 128;

/// The loader's configuration for this SDK, given the dispatch that owns the
/// table.
///
/// `dispatch` is the generated module, passed as a type by the dispatch itself
/// so that this file never has to import it. The direction is one-way on
/// purpose: the descriptor knows what the loader needs, the dispatch knows what
/// the header said, and neither imports the other.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Named in the pre-load panic, so the message says which library was
        /// reached for before it was loaded.
        pub const library_name = "sheenbidi";

        /// The table the generated dispatch declares, and the symbols it needs
        /// to fill it. Both come from the translated header, not from this file.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// The project's namespaced synchronization binding.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        /// One resolved address into one optional table field, and the empty
        /// case beside it. Both index `optional_symbols`, not `symbols`.
        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// The checks that run after every symbol resolved and before anything
        /// is published. A non-null answer closes the candidate and publishes
        /// nothing, and the caller may retry explicitly.
        pub fn validate(dst: *const table) ?[]const u8 {
            return validateVersion(dst) orelse
                validateCodePointTables(dst) orelse
                validateSequenceLayout(dst);
        }

        /// `SBVersionGetString`, `Headers/SheenBidi/SBVersion.h:37`: the
        /// provider's own sentinel-terminated string.
        ///
        /// The walk stops at the terminator and gives up after
        /// `max_version_len` bytes, so an unterminated pointer is refused
        /// rather than followed.
        fn validateVersion(dst: *const table) ?[]const u8 {
            const version: [*c]const u8 = dst.SBVersionGetString();
            var length: usize = 0;
            while (length < max_version_len) : (length += 1) {
                if (version[length] == 0) break;
            }
            if (length == 0) {
                return "SBVersionGetString() answered with an empty string, so this " ++
                    "provider is not the library this header describes";
            }
            if (length == max_version_len) {
                return "SBVersionGetString() answered with no terminator within " ++
                    "128 bytes, so this provider is not the library this header " ++
                    "describes";
            }
            return null;
        }

        /// `SBCodepointGetBidiType` and `SBCodepointGetScript`,
        /// `Headers/SheenBidi/SBCodepoint.h:86` and `:116`.
        ///
        /// LATIN CAPITAL LETTER A has been `L` and HEBREW LETTER ALEF has been
        /// `Hebr` in every Unicode revision SheenBidi has shipped
        /// (`Tools/Unicode/DerivedBidiClass.txt`, `Scripts.txt`), so these two
        /// answers identify the library without identifying a data revision. A
        /// one-byte scalar crossing the boundary that came back as something
        /// else means the widths do not agree, which is exactly the mismatch a
        /// symbol lookup cannot see.
        fn validateCodePointTables(dst: *const table) ?[]const u8 {
            const latin_a: dispatch.SBCodepoint = 0x0041;
            const hebrew_alef: dispatch.SBCodepoint = 0x05D0;

            const type_a: dispatch.SBBidiType = @intCast(dispatch.SBBidiTypeL);
            if (dst.SBCodepointGetBidiType(latin_a) != type_a) {
                return "SBCodepointGetBidiType(U+0041) did not answer SBBidiTypeL, " ++
                    "so this provider is not the library this header describes";
            }
            const script_alef: dispatch.SBScript = @intCast(dispatch.SBScriptHEBR);
            if (dst.SBCodepointGetScript(hebrew_alef) != script_alef) {
                return "SBCodepointGetScript(U+05D0) did not answer SBScriptHEBR, " ++
                    "so this provider is not the library this header describes";
            }
            return null;
        }

        /// `SBAlgorithmCreate` and `SBAlgorithmRelease`,
        /// `Headers/SheenBidi/SBAlgorithm.h:38` and `:119`.
        ///
        /// The `SBCodepointSequence` below is built by this dispatch from its
        /// own re-exported type, so the field offsets, the field order and the
        /// `SBUInteger` length are this build's, and the provider reads exactly
        /// that. A provider laid out differently would have to answer here to
        /// pass, which is what this observation is for. The object is released
        /// again before returning, so a provider that passes leaves nothing
        /// allocated.
        fn validateSequenceLayout(dst: *const table) ?[]const u8 {
            var units = [_]u8{ 'a', 'b' };
            const sequence: dispatch.SBCodepointSequence = .{
                .stringEncoding = @intCast(dispatch.SBStringEncodingUTF8),
                .stringBuffer = &units,
                .stringLength = units.len,
            };
            const algorithm = dst.SBAlgorithmCreate(&sequence);
            if (algorithm == null) {
                return "SBAlgorithmCreate() returned NULL for a two-code-unit " ++
                    "sequence, so this provider is not the library this header " ++
                    "describes";
            }
            dst.SBAlgorithmRelease(algorithm);
            return null;
        }
    };
}