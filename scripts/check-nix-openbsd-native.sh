#!/usr/bin/env bash
# Evaluate the native Nix derivation without attempting a cross-build.
set -euo pipefail
export NIX_OPENBSD_REPO
NIX_OPENBSD_REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
exec nix eval --impure --show-trace --raw --expr '
  let
    repo = builtins.getEnv "NIX_OPENBSD_REPO";
    flake = builtins.getFlake ("path:" + repo);
    pkgs = import flake.inputs.nixpkgs {
      system = "x86_64-openbsd";
      overlays = [ (import (repo + "/overlays/openbsd.nix")) ];
    };
  in pkgs.nix.drvPath
'
