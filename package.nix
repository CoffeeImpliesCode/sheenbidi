# SPDX-License-Identifier: Apache-2.0
#
# One source-only derivation, called from flake.nix and devenv.nix through
# pkgs.callPackage. It returns ONE derivation; the static and shared variants
# exist only at those two entry points, as `linkage`.
#
# The build graph owns everything about the library: the C flags, the source
# list, the header configuration and every file that is installed, including the
# licence, provenance and Unicode closure. This file chooses the optimize mode,
# the CPU baseline, the artifact kind and the prefix, and adds no C flag.
#
# `linkage` selects the artifact, not the dispatch. `static` means a static
# library artifact: SheenBidi allocates with malloc/free and copies with
# memcpy/memmove, so no variant of this package promises a wholly static
# executable.
{ lib, stdenv, zig, linkage ? "static" }:

assert lib.assertMsg (linkage == "static" || linkage == "dynamic")
  "sheenbidi: linkage must be static or dynamic, got ${toString linkage}";
assert lib.assertMsg (zig.version == "0.16.0")
  "sheenbidi: built with Zig 0.16.0, got ${zig.version}";

stdenv.mkDerivation {
  pname = "sheenbidi";
  version = "3.0.0";

  # Everything the build compiles, installs and tests stays; version control,
  # caches, previous outputs, devenv state and result links do not.
  #
  # The two lock files are dropped for a different reason, and it is not that
  # they are machine state: `flake.lock` is package content and ships, in
  # `build.zig.zon` `.paths`, so a fetched copy carries the pin its `flake.nix`
  # declares. It is excluded here because `zig build` never reads it. This is
  # the build's input, not the package's contents, and a file the build does not
  # read has no reason to be in it. `devenv.lock` is excluded on the same
  # ground, and is absent from the tree in any case.
  src = lib.cleanSourceWith {
    src = ./.;
    filter =
      path: _type:
      let
        base = baseNameOf (toString path);
      in
      !(builtins.elem base [
        ".git"
        ".jj"
        ".hg"
        ".svn"
        ".zig-cache"
        "zig-cache"
        "zig-out"
        "zig-pkg"
        ".devenv"
        ".devenv.flake.nix"
        "devenv.local.nix"
        ".direnv"
        "flake.lock"
        "devenv.lock"
      ]) && base != "result" && !(lib.hasPrefix "result-" base);
  };

  nativeBuildInputs = [ zig ];

  # Upstream ships CMakeLists.txt and meson.build. Neither is used: the library
  # is compiled by `zig build`, and letting stdenv configure either would build
  # the same C a second way with upstream's flags.
  dontUseCmake = true;
  dontUseMeson = true;

  # Install only. `dontInstall` must stay unset: the Zig setup hook's real
  # install phase is what installs anything.
  dontConfigure = true;
  dontBuild = true;
  dontCheck = true;
  dontUseZigCheck = true;
  # The hook would otherwise append its own `-Dcpu=baseline --release=safe`.
  dontSetZigDefaultFlags = true;

  installPhase = ''
    # Both caches inside the build sandbox's TMPDIR, never in the source tree.
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"

    zig build install \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=ReleaseSafe \
      -Dcpu=baseline \
      -Dlinkage=${linkage} \
      --prefix "$out" \
      --summary all
  '';

  # No `postInstall`, and none is needed: `build.zig` is the sole writer of
  # every path this output carries, `lib/pkgconfig/SheenBidi.pc` among them.
  # This file therefore adds no file of its own and holds no list of the
  # install's paths, so there is no second place in which any of them can be
  # described wrongly.
  #
  # An earlier version of this derivation did add one, and it was not a copy.
  # It filled `sheenbidi.pc.in` into `$out/lib/pkgconfig/sheenbidi.pc` while the
  # graph was already installing `SheenBidi.pc` beside it: a lower-case base
  # name and a capitalised one, both carrying `Name: SheenBidi`, so one library
  # was described by two files and `pkg-config` answered according to the
  # spelling it was asked for. The two disagreed on the only value that depends
  # on the variant — this file substituted `@SHEENBIDI_PKGCONFIG_CFLAGS@` with
  # nothing, where `build.zig`'s `addPkgConfig` writes `-DSB_CONFIG_DLL_IMPORT`
  # into `Cflags:` for a dynamic build, so a shared output's metadata described
  # the wrong decoration.
  #
  # Nothing has to fix a prefix for the graph's file to be correct here. It
  # writes `prefix` as `${pcfiledir}/../..`, relative to the `.pc` file itself,
  # which pkg-config resolves against the file it found; `$out` is a prefix
  # like any other to it.

  meta = {
    description = "SheenBidi, a lightweight implementation of the Unicode Bidirectional Algorithm (UAX #9), compiled from upstream's own C";
    longDescription = ''
      Upstream SheenBidi 3.0.0 (Apache-2.0), compiled from the C sources carried
      in this package. The output also installs the licence, provenance and
      Unicode-data closure; see share/doc/sheenbidi/NOTICE.md for the per-file
      inventory, including the eleven Unicode data files that are not
      Apache-2.0 material.
    '';
    homepage = "https://github.com/Tehreer/SheenBidi";
    license = lib.licenses.asl20;
    platforms = lib.platforms.unix ++ lib.platforms.windows;
  };
}