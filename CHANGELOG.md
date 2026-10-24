# CHANGELOG

- Propagate Debug static archive UBSan requirements to C and Zig system consumers; omit static-only WASI from dynamic checks.

Fork changes relative to SheenBidi v3.0.0.

- Port to Zig 0.17.0.
- `-fsys=sheenbidi` binds an installed host library (off by default) and rejects foreign targets.
- Devenv tasks locate this checkout and use caller-selected external cache/output paths; build tasks use eight jobs.
- Corrected previous UTF-8 and UTF-16 decoder docs: index zero is out of range and remains unchanged.
- The build graph alone installs `SheenBidi.pc`, with flags matching the linkage variant.
- Added runtime dispatch with `-Druntime`; load an explicit provider without changing the installed artifact.
- Nix exposes static/shared outputs through one source-only derivation; `-Dlinkage` selects the artifact and static is the default.
- Install closures include the library, headers, licence and provenance documents, and the eleven Unicode data files with their own terms.
- Fork-authored files are Apache-2.0 under direct owner authorization; upstream files and Unicode data are excluded.
- Build the upstream C90 unity source and leave its experimental text API disabled.
- Added the Zig 0.16 package `sheenbidi`, a typed facade over upstream's C library; the package manifest has no dependencies.
