# SPDX-License-Identifier: Apache-2.0
{
  description = "SheenBidi 3.0.0 — the Unicode Bidirectional Algorithm, compiled from upstream's own C and packaged for Zig 0.17.0";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/02c087f3fe673c9e317f206a627cb6b910336dbe";
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
          default = pkgs.callPackage ./package.nix { zig = pkgs.zig_0_17; };
          static = pkgs.callPackage ./package.nix { zig = pkgs.zig_0_17; };
          shared = pkgs.callPackage ./package.nix {
            zig = pkgs.zig_0_17;
            linkage = "dynamic";
          };
        }
      );
    };
}