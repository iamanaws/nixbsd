nixpkgsPath: hostPlatform:

if hostPlatform.isFreeBSD then
  [
    ./config/i18n-freebsd.nix
    ./programs/passwd.nix
    ./programs/services-mkdb.nix
    ./programs/shutdown-freebsd.nix
    ./programs/su.nix
    ./services/newsyslog.nix
    ./services/syslogd.nix
    ./services/ttys/getty-freebsd.nix
    ./system/boot/init/portable/freebsd.nix
    ./system/boot/loader/stand-freebsd
    ./system/service/freebsd/system.nix
    ./virtualisation/jails.nix
  ]
else if hostPlatform.isOpenBSD then
  [
    ./programs/passwd-openbsd.nix
    ./programs/shutdown-openbsd.nix
    ./programs/su-openbsd.nix
    ./security/bsd-auth-openbsd.nix
    ./services/ttys/getty-openbsd.nix
    ./system/boot/loader/stand-openbsd
    ./system/boot/init/portable/openbsd.nix
  ]
else
  throw "Unsupported target platform ${hostPlatform.system}"
