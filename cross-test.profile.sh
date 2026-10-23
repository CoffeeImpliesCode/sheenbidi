#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Uses cross-test's standard Zig build mode and the published 0.17.0 Tier 1/2 matrix.
# Set CROSS_LIBC_RUNTIMES externally for foreign GNU/musl loaders.

# Run the public Zig API tests.
CROSS_BUILD_STEP=test

# Two workers per target keep the large UCD test builds moving.
CROSS_BUILD_JOBS=2

# Per-target compile-and-run timeout in seconds.
CROSS_BUILD_TIMEOUT=3600

# Per-test-binary timeout in seconds for UCD conformance replay.
CROSS_TIMEOUT=1800
