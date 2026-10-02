#!/usr/bin/env bash
# cross-test.profile.sh — settings only, for the `cross-test` harness.
#
# `cross-test` is run from this package root. It compiles and runs this
# package's real `test` step, `zig build test -Dtarget=TARGET`, once per target
# of the published Zig 0.16.0 Tier 1/2 matrix (53 platforms), and it owns the
# matrix, the runner policy and the QEMU/Wine/Wasmtime detection. This file
# configures none of that and must not: it holds ordinary Bash variable
# definitions only, no `cross_build_command`/`cross_artifact` hooks (so the
# standard Zig-build mode is used), no `CROSS_MATRIX` and no `TARGETS` (so the
# full published matrix is selected, never a subset), and no host-specific
# path. Every value here is a default that the command line overrides, so
# `cross-test --jobs N --build-jobs N --build-timeout N --timeout N` still
# wins; see `cross-test --help`.
#
# `CROSS_LIBC_RUNTIMES` is deliberately absent: it names a directory of foreign
# libc loaders on the machine running the harness, which is that machine's
# business and not this package's. Supply it in the environment when a
# GNU-libc or dynamically linked musl cell needs one.
#
# Licence: **none asserted.** This is a fork-authored file, like `build.zig`,
# `zig/root.zig`, `tests.zig` and `consumer/`. Upstream SheenBidi is
# Apache-2.0 and that grant is untouched; it does not reach this file, and
# `NOTICE.md` records the fork's own files as unassigned.

# The step that runs the public Zig API tests. This is the harness default too;
# it is named here so the package's contract is in the package.
CROSS_BUILD_STEP=test

# One target at a time inside one `zig build`. The `test` step builds the C
# core and the translation three times over — once for the default graph, once
# each for Debug and ReleaseSafe — and `zig build test` also embeds
# `Tools/Unicode/BidiTest.txt` (7.6 MB) and `Tools/Unicode/BidiCharacterTest.txt`
# (6.6 MB) into each of the two test binaries. Two parallel jobs per target
# keeps that from serialising.
CROSS_BUILD_JOBS=2

# Deadline for one `zig build test -Dtarget=…`, covering both the compile and
# the run of that target's two test binaries.
CROSS_BUILD_TIMEOUT=3600

# Per-test-binary deadline, passed on as `zig build --test-timeout`. The
# conformance tests replay every row of `BidiTest.txt` (490,846 rows, 770,241
# row/direction cases) and of `BidiCharacterTest.txt` (91,707 rows) in each of
# Debug and ReleaseSafe; on a cell whose runner is an emulator rather than the
# host that is a long run, so the default 300 s is not a ceiling this package
# can meet. No run of the full matrix has been observed here yet.
CROSS_TIMEOUT=1800
