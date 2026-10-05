# SPDX-License-Identifier: Apache-2.0
#
# Tools, not the SDK: nothing here builds SheenBidi when the shell opens.
# `outputs.static` and `outputs.shared` are the same `package.nix` the flake
# uses, so `devenv build outputs.static` (or `outputs.shared`) is the packaging
# route from inside a shell. The attributes are lazy and nothing evaluates them
# until that command asks.
#
# State location is the caller's. Supply `TMPDIR`, `DEVENV_HOME`,
# `XDG_RUNTIME_DIR` and the Zig caches on approved local scratch before entering
# the shell; this file hard-codes no mount, account or store path and erases none
# of those variables.
#
# Every task below changes into this checkout before it runs anything, at a path
# this file evaluates rather than one it inherits. A task cannot trust the
# directory it is handed: `devenv --from path:<this SDK>` generates the wrapper
# with the *project* directory as its working directory, `DEVENV_ROOT` names that
# project, and `devenv tasks run` does not run `enterShell` either — so neither
# inherited location is this SDK. That is what `sheenbidi:consumer` and
# `sheenbidi:integrity` hit on 2026-10-04: `line 3: cd: consumer: No such file
# or directory` and `sha256sum: UPSTREAM.sha256: No such file or directory`, from
# a run in which this file parsed and every task name loaded (receipts
# `…-sheenbidi-devenv-consumer.log`, `…-sheenbidi-devenv-integrity.log`).
#
# A command that writes build output writes it outside this checkout: `build`
# and `install` take an explicit `--prefix` beneath the caller's Zig local cache
# (else `$XDG_CACHE_HOME`, else `$TMPDIR`), and `test`, `smoke`, `check` and
# `consumer` install nothing at all, so they are given nothing to redirect. A
# caller's own `--prefix` in `"$@"` still overrides both defaults.
#
# Every task that reaches `zig build` also takes an explicit `--cache-dir` under
# that same scratch root, and exports `ZIG_LOCAL_CACHE_DIR` and
# `ZIG_GLOBAL_CACHE_DIR` before the compiler starts, so no task can fall back to
# `.zig-cache/` at a build root in this checkout or in `consumer/`. A caller's own
# values of those two variables are kept rather than replaced, and a
# `--cache-dir` or `--global-cache-dir` arriving in `"$@"` is still the last word.
{ pkgs, ... }:

let
  zig = pkgs.zig_0_16;

  # This module's own directory, rendered once as one shell word. Every task
  # below changes into it — or into `consumerRoot` — before it runs anything.
  #
  # `./.` is the directory of the file that writes it, so it is this checkout by
  # construction rather than by where the caller stood. `builtins.toString` makes
  # it a plain string instead of a path value left inside the generated wrapper,
  # and `pkgs.lib.escapeShellArg` is this workspace's quoting convention
  # (`htscodecs/package.nix` uses the same function), so a checkout path
  # containing a space cannot split the command.
  #
  # Whether Nix renders that string as this working tree or as a store copy of it
  # is a property of how a path literal stringifies, not of this expression. No
  # run has observed which of the two it is, and either rendering contains the
  # `build.zig`, `UPSTREAM.sha256` and `consumer/` these tasks read.
  sdkRoot = pkgs.lib.escapeShellArg (builtins.toString ./.);
  consumerRoot = pkgs.lib.escapeShellArg (builtins.toString ./. + "/consumer");

  # Where a command below is allowed to write build output, and the caches its
  # `zig build` must not be left to keep on its own. The root is derived, never
  # invented: the Zig local cache the caller exported, else `$XDG_CACHE_HOME`,
  # else `$TMPDIR`. There is no `/tmp` fallback — a small system temporary
  # filesystem is not approved storage — and none into this checkout, which sits
  # on an NFS volume. With none of the three exported the command names the
  # variable to set and exits non-zero instead of writing where it was told not
  # to.
  #
  # A caller's own `--prefix`, arriving in `"$@"`, is still the last word: the
  # `--prefix` given beside it is a default, which is the convention `install`
  # already used.
  #
  # The two cache variables are set here rather than in `enterShell`, because
  # `devenv tasks run --mode single` does not run `enterShell`. A caller that
  # exported either of them keeps its own value; a caller that exported neither
  # gets the local cache beneath this scratch root and the global cache beneath
  # `$XDG_CACHE_HOME` else `$TMPDIR`, both created before zig starts. Without
  # that a `zig build` keeps `.zig-cache/` at its own build root — this checkout,
  # or `consumer/`'s — and `$HOME/.cache/zig` beside it, and neither is approved.
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
    # Only for the optional `-fsys=sheenbidi` mode, where the build asks
    # pkg-config about an already-installed SheenBidi. This environment ships no
    # system SheenBidi, and no result in this package depends on one.
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
      assertion = zig.version == "0.16.0";
      message = "sheenbidi: built with Zig 0.16.0; this nixpkgs has ${zig.version}.";
    }
  ];

  tasks = {
    # `zig build` with no step name is the install step: the library, the
    # headers, `SheenBidi.pc` and the licence records, all of which `build.zig`
    # attaches to `b.getInstallStep()` (`build.zig:979`). Left alone it writes
    # `zig-out/` into this NFS checkout, so it gets an external prefix under the
    # caller's scratch. The step is unchanged, the flags are `--cache-dir`,
    # `--prefix`, `-j8` and `--summary all`, and `"$@"` is still forwarded last,
    # so a caller's own flag still reaches zig behind this file's own.
    "sheenbidi:build".exec = ''
      cd ${sdkRoot} || exit 1
      ${scratchRoot}
      mkdir -p "$scratch/build"
      zig build --cache-dir "$ZIG_LOCAL_CACHE_DIR" --prefix "$scratch/build" -j8 --summary all "$@"
    '';

    # `test`, `smoke`, `check` and `consumer` carry no `--prefix`, because their
    # steps depend on test, run and compile steps only and never on
    # `b.getInstallStep()` (`build.zig:1232`, `:1203`, `consumer/build.zig:79`):
    # they install nothing, so there is no delivery output to redirect. Their
    # caches are external all the same: the snippet above fills a missing Zig
    # cache from `$XDG_CACHE_HOME` else `$TMPDIR` and `--cache-dir` names that
    # same directory, so none of them can leave `.zig-cache/` at its build root.

    # Debug and ReleaseSafe in one command: the `test` step runs both itself, so
    # -Doptimize would not narrow it.
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

    # Installs outside this checkout, for the same reason `build` does and by
    # the same rule. The step and `-Doptimize=ReleaseSafe` are unchanged,
    # `--cache-dir` is the same directory `build` uses, and `-j8 --summary all
    # "$@"` are exactly what they were.
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