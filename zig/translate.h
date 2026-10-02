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
 * SCOPE: the stable API only. Headers/SheenBidi/SBConfig.h ships every
 * SB_CONFIG_* macro commented out, so SB_TEXT_API_SUPPORTED is 0 and the bodies
 * of SBText.h, SBTextConfig.h and SBTextIterators.h expand to nothing. The
 * experimental text editing and analysis API is therefore absent from this
 * translation, and it is also absent from the archive: build.zig compiles
 * upstream's unity unit with SB_CONFIG_UNITY and without
 * SB_CONFIG_EXPERIMENTAL_TEXT_API, which is upstream's own default
 * (`meson_options.txt`: text_api disabled; CMakeLists.txt:
 * option(SB_CONFIG_EXPERIMENTAL_TEXT_API ... OFF)). Nothing here claims the
 * experimental API.
 *
 * `SB_CONFIG_UNITY` is deliberately absent: it only changes `SB_INTERNAL` to
 * `static` for the C library build. It says nothing about a consumer's view of
 * the headers, and setting it on a translation of declarations would be a lie.
 */

#include <SheenBidi/SheenBidi.h>
