# FORK-LICENSE.md — the licence of the files this fork authored

This file records one thing: what licence covers the files **this fork wrote**,
on whose authority, and what that grant deliberately does not reach.

It exists because upstream's licence text cannot answer that question. Apache-2.0
grants rights in *a work*; it does not extend to additions someone else made to a
distribution of that work. Until the owner authorized a term, the fork-authored
files in this package carried **no stated licence**, this file's predecessor
records said so explicitly, and `CHANGELOG.md` entries 14, 17 and 18 withdrew an
earlier Apache-2.0 offer that no one had made. That earlier state is what the
owner has now changed.

## The authorization

* **What was authorized:** a licence for this project's fork-authored additions,
  chosen per project, matching the primary upstream terms where that is
  appropriate.
* **Who authorized it:** the owner of this private downstream repository, directly,
  in the session that produced this package. It is not derived from upstream's
  terms, it is not inferred from another package in this workspace, and it is not
  upstream's decision to make.
* **When:** 2026-10-04.
* **What was chosen for this project, and why.** Upstream SheenBidi is
  `Apache-2.0` (`LICENSE`, shipped verbatim; the grant is restated at
  `README.upstream.md:169-184` under the copyright "Copyright (C) 2014-2026
  Muhammad Tayyab Akram"). `Apache-2.0` is therefore this fork's primary upstream
  term, and matching it keeps one licence for a tree whose overwhelming majority
  — `Headers/`, `Source/`, `Tools/`, `Tests/` — is upstream's. It also carries
  the obligations upstream's own text already imposes on this fork: a `NOTICE`
  file, a statement of what changed, and the patent-grant termination clause.
  Those obligations are met by [`NOTICE.md`](NOTICE.md), by
  [`CHANGELOG.md`](CHANGELOG.md) and by the patent section below.

## The grant

**SPDX identifier: `Apache-2.0`.**

The fork-authored files of this package — every file listed in
[`NOTICE.md`](NOTICE.md) under "Files this fork adds" and "The one upstream file
this fork edits" — are licensed under the Apache License, Version 2.0, whose full
text ships verbatim in this repository as `LICENSE`. That is the same licence, the
same text and the same version as upstream's own; the fork does not restate,
shorten or paraphrase it, and `LICENSE` is not edited.

Each newly authored or rewritten source and build file carries the same
identifier in its SPDX header, one line:

```
SPDX-License-Identifier: Apache-2.0
```

**No copyright line is asserted here, and none is inserted into any file.** This
package does not invent a copyright identity, and it does not attribute the fork's
additions to Muhammad Tayyab Akram or to any other upstream contributor. The
licensor of record is the owner of this downstream repository; whoever that is,
the grant is theirs and it is made here rather than inferred.

### What the grant covers

Every file this fork authored: the Zig build (`build.zig`, `build.zig.zon`), the
Nix and devenv packaging (`package.nix`, `flake.nix`, `devenv.nix`,
`devenv.yaml`, `.envrc`), the Zig facade and translation root (`zig/`), the
runtime route (`runtime/library.zig`, `runtime/graph.zig`, `runtime/misuse.zig`,
and the loader core they name — `runtime/loader.zig`, `runtime/generate.zig`,
`runtime/sync.c`, `runtime/sync.h` — named in [`NOTICE.md`](NOTICE.md)), the
tests, the example, the consumer package, the `cross-test` harness profile, this
fork's CI workflow, and the documentation set
(`README.md`, `README.zig.md`, `UPSTREAM.md`, `NOTICE.md`, `FORK-LICENSE.md`,
`CHANGELOG.md`, `FORK-NOTES.md`).

### What the grant does not cover

* **Upstream's own work.** `Headers/`, `Source/`, `Tools/`, `Tests/`,
  `CMakeLists.txt`, `Makefile`, `meson.build`, `meson_options.txt`,
  `SheenBidi.cmake.in`, `sheenbidi.pc.in`, `LICENSE` and `README.upstream.md` are
  upstream's, under upstream's terms. This fork grants nothing about them and
  relicenses nothing in them. Their terms are Apache-2.0 as upstream published
  them.
* **The eleven Unicode, Inc. data files in `Tools/Unicode/`.** They are not
  Apache-2.0 and are not covered by this grant. They are Unicode, Inc. data files
  under the terms their own first lines name, they travel unmodified with those
  notices intact, and neither this file nor `LICENSE` restates, paraphrases or
  overrides them. Verbatim, from `Tools/Unicode/BidiCharacterTest.txt:3-5`:
  ```
  # © 2025 Unicode®, Inc.
  # Unicode and the Unicode Logo are registered trademarks of Unicode, Inc. in the U.S. and other countries.
  # For terms of use and license, see https://www.unicode.org/terms_of_use.html
  ```
  Ten of the eleven name their own revision as well; `UnicodeData.txt` names
  nothing at all and is the exception an auditor must be told about rather than
  left to look for. Details in [`NOTICE.md`](NOTICE.md).
* **The `.gitignore` append.** `.gitignore` is upstream's file. Its first 27
  lines are kept verbatim and the fork appends its own ignore entries, so the
  file is not byte-identical to upstream and is excluded from the integrity
  record. The appended entries are fork-authored configuration, covered by this
  grant; the upstream lines above them are not.

### Apache-2.0 obligations that now apply to the fork's own files too

* **§4(a), a copy of the licence.** Shipped, verbatim, as `LICENSE`, and
  installed next to the library at `share/doc/sheenbidi/LICENSE` by both
  `zig build install` and the Nix derivation.
* **§4(b), a statement of changes.** [`NOTICE.md`](NOTICE.md) §"What this fork
  changed" and the numbered [`CHANGELOG.md`](CHANGELOG.md) entries.
* **§4(c), retaining notices.** No upstream file is edited except the recorded
  `.gitignore` append, so upstream's notices are retained by not touching them.
* **§4(d), attribution in a `NOTICE` file.** `NOTICE.md` is this fork's `NOTICE`
  file and carries the attribution. A downstream copy must include it.
* **§3, the patent grant and its termination.** The fork's own additions carry
  the same patent licence as the rest of the work, with the same termination:
  a patent licence granted here ends for any contributor whose contribution is
  the subject of patent litigation. See `NOTICE.md` §"Patent grant".

## Why the earlier "unassigned" record is not a contradiction

`NOTICE.md` said the fork's files were unassigned, `README.zig.md` repeated it,
and `CHANGELOG.md` entries 14, 17 and 18 withdrew an earlier unauthorised
Apache-2.0 offer. Those statements were correct when they were written and they
describe what was true then: no one had authorized a grant. This file is the
authorization and the grant that changed that. Where the older documents still
say "unassigned", this file supersedes them; the older statements stay in the
changelog because a changelog is the record of what was true when.