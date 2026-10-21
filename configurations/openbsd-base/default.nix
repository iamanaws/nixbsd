{
  pkgs,
  lib,
  config,
  ...
}:
{
  nixpkgs.hostPlatform = "x86_64-openbsd";
  nixpkgs.overlays = [
    (import ../../overlays/openbsd.nix)
  ];
  # Keep the OpenBSD-patched Nix package selected by the overlay.
  nixpkgs.overrideNix = false;
  boot.kernel.package = pkgs.openbsd.sys;

  boot.loader.stand-openbsd.enable = true;
  boot.loader.stand-openbsd.console = "com0";
  system.stateVersion = lib.mkDefault "26.11";

  fileSystems."/" = {
    device = "/dev/sd0a";
    fsType = "ffs";
    # Activation checks root before mounting it writable.
    noCheck = true;
  };

  users.mutableUsers = false;
  users.defaultUserShell = pkgs.bash;
  users.groups.kmem.gid = 2;
  users.groups.utmp.gid = 45;

  users.users.root.initialHashedPassword = "$2b$09$CexHNp84.dJLZv5oBcSBuO7zLdbAIBxyxiukAPwY3yKiH162s.GGW";

  users.users.bestie = {
    isNormalUser = true;
    description = "your bestie";
    extraGroups = [ "wheel" ];
    inherit (config.users.users.root) initialHashedPassword;
  };

  environment.systemPackages = [
    pkgs.openbsd.kdump
    pkgs.openbsd.ktrace
  ];
  environment.etc.myname.text = config.networking.fqdnOrHostName + "\n";

  environment.etc.ttys.text = lib.mkForce ''
    # name  getty                                      type   status
    console "${pkgs.openbsd.getty}/bin/getty std.9600" vt220  off secure
    tty00   "${pkgs.openbsd.getty}/bin/getty std.9600" vt220  on secure
  '';

  virtualisation.vmVariant.virtualisation = {
    diskImage = "./${config.system.name}.qcow2";
    graphics = false;
  };

  services.openssh.enable = true;
  openbsd.rc.conf.pf = false;

  xdg.mime.enable = false;
  documentation.enable = false;
  documentation.man.man-db.enable = false;
  programs.bash.completion.enable = false;
}
