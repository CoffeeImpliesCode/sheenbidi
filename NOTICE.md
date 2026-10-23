# NOTICE

## Upstream identity and attribution

SheenBidi, Unicode Bidirectional Algorithm implementation (UAX #9): <https://github.com/Tehreer/SheenBidi.git>, tag `v3.0.0`, commit `cfe430e7375a7845b679adae9d51dac6deaa8858`, library version `3.0.0`.

Copyright (C) 2014-2026 Muhammad Tayyab Akram.

`README.upstream.md` is upstream's README, preserved byte for byte from `README.md`. `LICENSE` is the full, unmodified Apache License 2.0 text; no copyright placeholder is filled.

## Per-path licences

| Paths | Terms and attribution |
|---|---|
| `Headers/`, `Source/`, `Tools/Generator/`, `Tools/Parser/`, `Tests/`, `CMakeLists.txt`, `Makefile`, `meson.build`, `meson_options.txt`, `SheenBidi.cmake.in`, `sheenbidi.pc.in`, `README.upstream.md` | Upstream SheenBidi work under Apache-2.0; upstream notices and grant are retained in `LICENSE` and source headers. |
| `Source/Data/BidiTypeLookup.{c,h}`, `GeneralCategoryLookup.{c,h}`, `PairingLookup.{c,h}`, `ScriptLookup.{c,h}` | Upstream-generated tables without per-file copyright or licence notices; covered by the upstream grant for `Source/`. |
| `Tools/Unicode/*.txt` (11 files) | Unicode, Inc. data under the terms in its own files; not Apache-2.0 and not relicensed here. Ten files carry the terms; `UnicodeData.txt` has no header. |

The eleven Unicode files are not covered by Apache-2.0. `UnicodeData.txt` begins with data, not a terms or revision notice; its UCD 17.0.0 provenance is inferred from the adjacent files and generated tables.

The Unicode notice, quoted verbatim from `Tools/Unicode/BidiCharacterTest.txt`:

```
# © 2025 Unicode®, Inc.
# Unicode and the Unicode Logo are registered trademarks of Unicode, Inc. in the U.S. and other countries.
# For terms of use and license, see https://www.unicode.org/terms_of_use.html
```

## Files this fork adds

These files are Apache-2.0 under direct owner authorization dated 2026-10-04; see `FORK-LICENSE.md`. No individual copyright identity is asserted, and no fork work is attributed to an upstream contributor. Newly authored or rewritten source and build files carry `SPDX-License-Identifier: Apache-2.0`.

| Paths | Contents |
|---|---|
| `build.zig`, `build.zig.zon` | Zig build graph and package manifest |
| `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc` | Nix packaging and development environment |
| `zig/` | Facade, translation header, ABI bridge, and conformance helpers |
| `runtime/` | Runtime library interface, build graph, misuse example, loader, symbol generator, and sync layer |
| `tests.zig`, `smoke.zig`, `consumer/`, `cross-test.profile.sh` | Tests, example, dependent-package consumer, and cross-test settings |
| `README.md`, `README.zig.md`, `UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`, `FORK-LICENSE.md`, `CHANGELOG.md`, `FORK-NOTES.md` | Fork documentation and provenance records |

## The one upstream file this fork edits

| File | Change and licence scope |
|---|---|
| `.gitignore` | The first 27 upstream lines remain unchanged. Only appended fork entries are covered by the owner grant; the edited file is not byte-identical to upstream and is excluded from `UPSTREAM.sha256`. |

## Apache-2.0 patent grant

The following Apache-2.0 §3 text is quoted verbatim from `LICENSE`:

> where such license applies only to those patent claims licensable by such
> Contributor that are necessarily infringed by their Contribution(s) alone or
> by combination of their Contribution(s) with the Work to which such
> Contribution(s) was submitted. If You institute patent litigation against any
> entity (including a cross-claim or counterclaim in a lawsuit) alleging that the
> Work or a Contribution incorporated within the Work constitutes direct or
> contributory patent infringement, then any patent licenses granted to You under
> this License for that Work shall terminate as of the date such litigation is
> filed.
