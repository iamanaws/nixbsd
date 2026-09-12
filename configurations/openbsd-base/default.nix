{
  pkgs,
  lib,
  config,
  ...
}:
{
  nixpkgs.hostPlatform = "x86_64-openbsd";
  nixpkgs.overlays = [
    (import ../../overlays/nix-patches.nix)
    (import ../../overlays/openbsd.nix)
  ];
  nixpkgs.overrideNix = false;
  boot.kernel.package = pkgs.openbsd.sys;

  boot.loader.stand-openbsd.enable = true;
  boot.loader.stand-openbsd.console = "com0";
  system.includeInstallerDependencies = false;
  system.stateVersion = lib.mkDefault "26.11";

  fileSystems."/" = {
    device = "/dev/sd0a";
    fsType = "ffs";
  };
  fileSystems."/boot/efi" = {
    device = "/dev/sd0i";
    fsType = "msdos";
  };

  users.mutableUsers = false;
  users.defaultUserShell = pkgs.bash;
  users.groups.kmem.gid = 2;
  users.groups.utmp.gid = 45;

  # users.users.root.initialPassword = "toor";
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

  environment.etc.ttys.text = lib.mkForce ''
    # name  getty                                      type   status
    console "${pkgs.openbsd.getty}/bin/getty std.9600" vt220  off secure
    tty00   "${pkgs.openbsd.getty}/bin/getty std.9600" vt220  on secure
  '';

  virtualisation.vmVariant.virtualisation = {
    diskImage = "./${config.system.name}.qcow2";
    graphics = false;
  };

  services.fcron.enable = false;

  fonts.fontconfig.enable = false;
  xdg.mime.enable = false;
  documentation.enable = false;
  documentation.man.man-db.enable = false;
  programs.bash.completion.enable = false;
}
