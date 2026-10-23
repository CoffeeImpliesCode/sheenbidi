# SPDX-License-Identifier: Apache-2.0
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