# Fork licence

The licensor is the owner of this private downstream repository. The owner authorized Apache-2.0 for this package on 2026-10-04. No individual copyright line is asserted or added, and no upstream contributor is credited for fork-authored files.

## Grant

**SPDX identifier: `Apache-2.0`.**

The fork-authored files of this package — every file listed in `NOTICE.md` under "Files this fork adds" and "The one upstream file this fork edits" — are licensed under the Apache License, Version 2.0, whose full text ships verbatim in this repository as `LICENSE`. That is the same licence, the same text and the same version as upstream's own; the fork does not restate, shorten or paraphrase it, and `LICENSE` is not edited.

Each newly authored or rewritten source and build file carries this identifier in its SPDX header:

```
SPDX-License-Identifier: Apache-2.0
```

### Covered files

The grant covers every fork-authored file: `build.zig`, `build.zig.zon`; `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc`; the Zig facade and translation root in `zig/`; `runtime/library.zig`, `runtime/graph.zig`, `runtime/misuse.zig`, `runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c`, `runtime/sync.h`; tests, example, consumer package, and `cross-test.profile.sh`; and `README.md`, `README.zig.md`, `UPSTREAM.md`, `NOTICE.md`, `FORK-LICENSE.md`, `CHANGELOG.md`, and `FORK-NOTES.md`.

### Not covered by this grant

Upstream's work remains under its Apache-2.0 terms: `Headers/`, `Source/`, `Tools/`, `Tests/`, `CMakeLists.txt`, `Makefile`, `meson.build`, `meson_options.txt`, `SheenBidi.cmake.in`, `sheenbidi.pc.in`, `LICENSE`, and `README.upstream.md`. This fork grants no rights in those files and relicenses none of them.

The eleven Unicode, Inc. data files in `Tools/Unicode/` are not Apache-2.0 and are excluded from this grant. They remain under the terms in their own first lines, travel unmodified with their notices, and are not relicensed by this file or `LICENSE`. From `Tools/Unicode/BidiCharacterTest.txt`:

```
# © 2025 Unicode®, Inc.
# Unicode and the Unicode Logo are registered trademarks of Unicode, Inc. in the U.S. and other countries.
# For terms of use and license, see https://www.unicode.org/terms_of_use.html
```

Ten files state their revision; `UnicodeData.txt` does not. `NOTICE.md` records the file list.

`.gitignore` is upstream's file: its first 27 lines remain unchanged, and the fork's appended entries alone are covered by this grant. The append makes the file non-identical to upstream and excludes it from `UPSTREAM.sha256`.

## Apache-2.0 obligations

- Section 4(a): `LICENSE` ships with the package and is installed at `share/doc/sheenbidi/LICENSE` by `zig build install` and the Nix derivation.
- Section 4(b): `NOTICE.md` and `CHANGELOG.md` state the changes.
- Section 4(c): upstream notices remain; `.gitignore` is the only upstream file with a recorded append.
- Section 4(d): `NOTICE.md` carries attribution and must accompany downstream copies.
- Section 3: fork additions carry the patent licence and termination clause. A patent licence ends for any contributor whose contribution is the subject of patent litigation.
