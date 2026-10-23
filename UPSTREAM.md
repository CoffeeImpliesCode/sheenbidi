# UPSTREAM

| Item | Value |
|---|---|
| Project | SheenBidi, Unicode Bidirectional Algorithm implementation (UAX #9) |
| Repository | <https://github.com/Tehreer/SheenBidi.git> |
| Pinned release | tag `v3.0.0`; C library version `3.0.0` |
| Commit | `cfe430e7375a7845b679adae9d51dac6deaa8858` |
| Library licence | Apache-2.0; see `NOTICE.md` |
| Upstream copyright | Copyright (C) 2014-2026 Muhammad Tayyab Akram |
| Source acquisition | Full clone of the canonical repository; upstream Git history is retained. |
| Full-tree archive SHA-256 | `9bdf0c279f5070f9d397d8f1446acd0bf8eebb802da80ca4cb6b57fb1cac4a28` |

The upstream README is preserved byte for byte as `README.upstream.md`; `README.md` is fork-authored.

## Shipped upstream paths

The 218 upstream files recorded by `UPSTREAM.sha256` are the upstream-owned entries among the package paths:

| Path | Files | Contents |
|---|---:|---|
| `Headers/` | 23 | Public headers |
| `Source/` | 75 | C library, headers, and generated data tables |
| `Tools/` | 60 | Unicode data, parser, generator, and conformance fixtures |
| `Tests/` | 52 | Upstream test sources |
| Root build and licence files | 8 | `CMakeLists.txt`, `Makefile`, `meson.build`, `meson_options.txt`, `SheenBidi.cmake.in`, `sheenbidi.pc.in`, `LICENSE`, `README.upstream.md` |

`.gitignore` retains its first 27 upstream lines and has fork-authored ignore entries appended; the edited file is excluded from `UPSTREAM.sha256` because it is not byte-identical to upstream.

## Removed upstream files

None from the shipped paths listed above; `.gitignore` is appended, and the upstream README is preserved under its renamed path.

## Integrity record

`UPSTREAM.sha256` contains one SHA-256 record for each of the 218 shipped upstream files. Check the listed paths with `sha256sum -c UPSTREAM.sha256`.
