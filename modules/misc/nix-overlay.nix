{
  config,
  lib,
  ...
}:
with lib;
{
  options = {
    # TODO: remove when stable nix >= 2.35
    nixpkgs.overrideNix = mkOption {
      type = types.bool;
      default = true;
      example = false;
      description = ''
        Overlay nix with the latest version of nix.

        This only works when building with a flake and `nixpkgs.pkgs` is not set manually.

        When this option is enabled then the overlay is enabled so that
        packages and options that require a working nix can build.
      '';
    };
  };

  config = {
    nixpkgs.overlays =
      lib.optionals config.nixpkgs.overrideNix [
        (_: prev: { nix = prev.nixVersions.latest; })
      ]
      ++ [ (import ../../overlays/pkgs.nix) ];
  };
}
