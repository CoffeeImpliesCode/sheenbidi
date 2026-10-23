# SPDX-License-Identifier: Apache-2.0
# Development tools only; shell entry does not build the SDK.
# Tasks keep build outputs and Zig caches in caller-approved scratch.
{ pkgs, ... }:

let
  zig = pkgs.zig_0_17;

  # Resolve checkout paths independently of the caller's working directory.
  sdkRoot = pkgs.lib.escapeShellArg (builtins.toString ./.);
  consumerRoot = pkgs.lib.escapeShellArg (builtins.toString ./. + "/consumer");

  # Keep outputs and Zig caches in caller-approved scratch, not this NFS checkout.
  # Require ZIG_LOCAL_CACHE_DIR, XDG_CACHE_HOME or TMPDIR; there is no /tmp fallback.
  scratchRoot = ''
    if [ -n "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      scratch="''${ZIG_LOCAL_CACHE_DIR}/sheenbidi"
    elif [ -n "''${XDG_CACHE_HOME:-}" ]; then
      scratch="''${XDG_CACHE_HOME}/sheenbidi"
    elif [ -n "''${TMPDIR:-}" ]; then
      scratch="''${TMPDIR}/sheenbidi"
    else
      echo "sheenbidi: set ZIG_LOCAL_CACHE_DIR, XDG_CACHE_HOME or TMPDIR to approved scratch; this checkout is on an NFS volume and is not a build or install location." >&2
      exit 1
    fi
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
      ZIG_LOCAL_CACHE_DIR="$scratch/cache"
    fi
    if [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        ZIG_GLOBAL_CACHE_DIR="''${XDG_CACHE_HOME}/zig"
      elif [ -n "''${TMPDIR:-}" ]; then
        ZIG_GLOBAL_CACHE_DIR="''${TMPDIR}/zig"
      else
        echo "sheenbidi: set ZIG_GLOBAL_CACHE_DIR, XDG_CACHE_HOME or TMPDIR to approved scratch; this checkout is on an NFS volume and is not a build or install location." >&2
        exit 1
      fi
    fi
    mkdir -p "$ZIG_LOCAL_CACHE_DIR" "$ZIG_GLOBAL_CACHE_DIR"
    export ZIG_LOCAL_CACHE_DIR ZIG_GLOBAL_CACHE_DIR
  '';
in
{
  packages = [
    zig
    # Needed only when -fsys=sheenbidi asks pkg-config for an installed library.
    pkgs.pkg-config
  ];

  outputs = {
    default = pkgs.callPackage ./package.nix { zig = zig; };
    static = pkgs.callPackage ./package.nix { zig = zig; };
    shared = pkgs.callPackage ./package.nix {
      zig = zig;
      linkage = "dynamic";
    };
  };

  assertions = [
    {
      assertion = zig.version == "0.17.0";
      message = "sheenbidi: built with Zig 0.17.0; this nixpkgs has ${zig.version}.";
    }
  ];

  tasks = {
    # Install outputs under scratch and forward caller flags.
    "sheenbidi:build".exec = ''
      cd ${sdkRoot} || exit 1
      ${scratchRoot}
      mkdir -p "$scratch/build"
      zig build --cache-dir "$ZIG_LOCAL_CACHE_DIR" --prefix "$scratch/build" -j8 --summary all "$@"
    '';

    # Test tasks do not install; keep their Zig caches outside the checkout.

    # Runs both Debug and ReleaseSafe; -Doptimize does not narrow the test step.
    "sheenbidi:test".exec = ''
      cd ${sdkRoot} || exit 1
      ${scratchRoot}
      zig build test --cache-dir "$ZIG_LOCAL_CACHE_DIR" -j8 --summary all "$@"
    '';

    "sheenbidi:smoke".exec = ''
      cd ${sdkRoot} || exit 1
      ${scratchRoot}
      zig build smoke --cache-dir "$ZIG_LOCAL_CACHE_DIR" -j8 --summary all "$@"
    '';

    "sheenbidi:check".exec = ''
      cd ${sdkRoot} || exit 1
      ${scratchRoot}
      zig build check --cache-dir "$ZIG_LOCAL_CACHE_DIR" -j8 --summary all "$@"
    '';

    # Install outputs under the same scratch root; caller flags still win.
    "sheenbidi:install".exec = ''
      cd ${sdkRoot} || exit 1
      ${scratchRoot}
      mkdir -p "$scratch/install"
      zig build install --cache-dir "$ZIG_LOCAL_CACHE_DIR" --prefix "$scratch/install" -Doptimize=ReleaseSafe -j8 --summary all "$@"
      printf '%s\n' "installed to $scratch/install"
    '';

    "sheenbidi:consumer".exec = ''
      cd ${consumerRoot} || exit 1
      ${scratchRoot}
      zig build run --cache-dir "$ZIG_LOCAL_CACHE_DIR" -j8 --summary all "$@"
    '';

    "sheenbidi:integrity".exec = ''
      cd ${sdkRoot} || exit 1
      sha256sum -c UPSTREAM.sha256 "$@"
    '';
  };

  enterShell = ''
    echo "sheenbidi — Zig $(zig version)"
    echo "packaging: devenv build outputs.static | outputs.shared"
    echo "tasks are namespaced sheenbidi:* and run this package's own build"
  '';
}