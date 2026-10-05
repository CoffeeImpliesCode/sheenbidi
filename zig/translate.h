// SPDX-License-Identifier: Apache-2.0
/*
 * Translation root for `zig translate-c`.
 *
 * `zig/root.zig` re-exports the translated declarations as `pub const c`, so
 * this header is the whole C surface the Zig facade is allowed to see. It is
 * an upstream aggregate include and nothing else: no macro is defined here, no
 * declaration is added, and no upstream header is edited.
 *
 * The angle-bracket spelling is deliberate. It is the include path that decides
 * which headers answer:
 *
 *   bundled mode   build.zig adds `-I Headers`, so <SheenBidi/SheenBidi.h> is
 *                  the checked-in tree of this repository.
 *   -fsys=sheenbidi build.zig adds no include path and lets pkg-config supply
 *                  its Cflags, so <SheenBidi/SheenBidi.h> is the header the
 *                  installed libSheenBidi was installed with. The declarations
 *                  that reach the facade and the archive that gets linked then
 *                  come from one place, which is the whole reason this wrapper
 *                  exists rather than translating Headers/SheenBidi/SheenBidi.h
 *                  directly.
 *
 * SCOPE: the stable API only, and specifically not the experimental text API.
 * Headers/SheenBidi/SBConfig.h:39 ships SB_CONFIG_EXPERIMENTAL_TEXT_API
 * commented out, so this build's selected configuration leaves it undefined
 * and SBBase.h:44-48 makes SB_TEXT_API_SUPPORTED 0. The bodies of SBText.h,
 * SBTextConfig.h and SBTextIterators.h therefore expand to nothing, and the
 * translation declares none of them. The same macro is undefined on the C
 * compile line, where the corresponding units under `Source/API` and
 * `Source/Text` contribute no definitions either, so the archive does not
 * hold what this header does not declare. Seven of the 23 installed public
 * headers are inside that guard and declare nothing in this configuration:
 * `SBText.h:27`, `SBTextConfig.h:23`, `SBTextIterators.h:24`,
 * `SBTextType.h:22`, `SBAttributeInfo.h:22`, `SBAttributeList.h:23` and
 * `SBAttributeRegistry.h:23`. Defining the macro in a consumer would be code
 * that does not link against this build, and no build variant here defines it.
 * That is upstream's own shipped default -
 * `meson_options.txt` disables the text API and CMakeLists.txt:18 defaults
 * SB_CONFIG_EXPERIMENTAL_TEXT_API to OFF - and it is a configuration this
 * package selects on both sides of the boundary, in every mode and in both
 * linkages. Nothing here claims the experimental API and nothing stubs it.
 *
 * `SB_CONFIG_UNITY` is deliberately absent: it only changes `SB_INTERNAL` to
 * `static` for the C library build. It says nothing about a consumer's view of
 * the headers, and setting it on a translation of declarations would be a lie.
 *
 * The two DLL macros are also absent here, and are supplied on the
 * translation line by build.zig instead. `SB_CONFIG_DLL_IMPORT` is defined
 * exactly when the library this translation will bind to is the shared one:
 * this graph's own `-Dlinkage=dynamic`, or `-Dlinkage=dynamic` in
 * `-fsys=sheenbidi` mode, where the option names the kind of *installed*
 * library rather than one this graph builds. build.zig puts it on the command
 * line rather than here so that a header checked into the tree never carries a
 * decision that depends on which artifact is being built, and so the decoration
 * cannot disagree with the library the linker is asked for. With it undefined,
 * `SB_PUBLIC` expands to nothing and every declaration below is a plain
 * `extern`, which is what a static archive and a plain `extern` both want;
 * with it defined on Windows, `SBBase.h:30-38` turns each one into a
 * `__declspec(dllimport)` declaration, which is how a translation declares a
 * symbol a DLL provides, and `zig translate-c` carries that through as
 * `is_dll_import` rather than discarding it with the macro. Nothing here
 * defines `SB_CONFIG_EXPERIMENTAL_TEXT_API`, `SB_CONFIG_ALLOW_NON_ATOMIC_FALLBACK`,
 * `SB_CONFIG_DLL_EXPORT` or `SB_CONFIG_DLL_IMPORT`.
 */

#include <SheenBidi/SheenBidi.h>
