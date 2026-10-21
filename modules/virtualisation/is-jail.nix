{ lib, ... }:
{
  options.boot.isJail = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Whether this NixBSD machine is a jail running in another NixBSD system.
    '';
  };
}
