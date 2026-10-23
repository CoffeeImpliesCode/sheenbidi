# SPDX-License-Identifier: Apache-2.0
#
# build.zig owns the source and install graph; linkage selects static or shared output.
# A static library does not imply a static executable; SheenBidi uses libc.
{ lib, stdenv, zig, linkage ? "static" }:

assert lib.assertMsg (linkage == "static" || linkage == "dynamic")
  "sheenbidi: linkage must be static or dynamic, got ${toString linkage}";
assert lib.assertMsg (zig.version == "0.17.0")
  "sheenbidi: built with Zig 0.17.0, got ${zig.version}";

stdenv.mkDerivation {
  pname = "sheenbidi";
  version = "3.0.0";

  # Keep package sources, but exclude generated and version-control state.
  # flake.lock ships in .paths but is not a build input.
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

  # Use the Zig build graph, not upstream's CMake or Meson phases.
  dontUseCmake = true;
  dontUseMeson = true;

  # Keep installPhase enabled; the Zig hook performs installation.
  dontConfigure = true;
  dontBuild = true;
  dontCheck = true;
  dontUseZigCheck = true;
  # The graph sets the target CPU and optimize mode.
  dontSetZigDefaultFlags = true;

  installPhase = ''
    # Keep Zig caches in the build sandbox's TMPDIR.
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

  # build.zig owns the install closure; do not add a second pkg-config file or fixed prefix.

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