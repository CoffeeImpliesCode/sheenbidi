# SPDX-License-Identifier: Apache-2.0
#
# sheenbidi/flake.nix — packages only.
#
# Three attributes per system, all the same derivation from `package.nix` with
# a different delivery choice:
#
#   packages.<system>.static   libSheenBidi.a
#   packages.<system>.shared   libSheenBidi.so
#   packages.<system>.default  == static, which is what this SDK has always
#                              produced; nothing here changes its linkage
#                              policy silently
#
# There is deliberately no `devShells` and no `formatter`. The development
# environment for this package is `devenv.nix` + `devenv.yaml` + `.envrc`, and
# it is deliberately lighter than a nix build of the SDK itself: entering the
# shell must not require compiling the library.
#
# `flake.lock` is owned by the workspace driver and is not written here. The
# nixpkgs input below is pinned by revision, not by a floating channel, so an
# evaluation that has a lock agrees with one that does not.
{
  description = "SheenBidi 3.0.0 — the Unicode Bidirectional Algorithm, compiled from upstream's own C and packaged for Zig 0.16.0";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";
  };

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forEachSystem =
        f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forEachSystem (
        pkgs:
        {
          default = pkgs.callPackage ./package.nix { zig = pkgs.zig_0_16; };
          static = pkgs.callPackage ./package.nix { zig = pkgs.zig_0_16; };
          shared = pkgs.callPackage ./package.nix {
            zig = pkgs.zig_0_16;
            linkage = "dynamic";
          };
        }
      );
    };
}