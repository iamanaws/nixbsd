# Exercise authentication and service login classes in a disposable VM.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  probeValue = "spaces 'quote' $dollar ; semicolon";
  askpass = pkgs.buildPackages.writeShellScript "openbsd-test-askpass" ''
    printf '%s\n' 'VmTest-New9!'
  '';
in
{
  imports = [ ../openbsd-base ];

  users.groups.service_probe = { };
  users.users.service_probe = {
    isSystemUser = true;
    group = "service_probe";
    extraGroups = [ "wheel" ];
  };
  users.classes.service_probe.settings = {
    tc = "daemon";
    openfiles = {
      cur = 64;
      max = 64;
    };
  };
  init.services.service-probe = {
    user = "service_probe";
    startType = "oneshot";
    dependencies = [ "FILESYSTEMS" ];
    before = [ "LOGIN" ];
    directory = "/tmp";
    environment.PROBE = probeValue;
    startCommand = [
      (pkgs.writeShellScript "service-probe" ''
        set -eu
        test "$(id -un)" = service_probe
        test "$(id -gn)" = service_probe
        id -Gn | grep -w wheel
        test "$PROBE" = ${lib.escapeShellArg probeValue}
        test "$PWD" = /tmp
        test "$(ulimit -Sn)" = 64
        test "$(ulimit -Hn)" = 64
        printf 'SERVICE_PROBE_OK\n' > /tmp/service-probe-result
      '')
    ];
  };

  init.services.argument-probe = {
    startType = "foreground";
    startCommand = [
      "${pkgs.coreutils}/bin/sleep"
      "300"
    ];
    dependencies = [ "FILESYSTEMS" ];
    before = [ "LOGIN" ];
  };

  system.build.authTest = pkgs.buildPackages.writeShellScriptBin "test-openbsd-auth" ''
    exec ${pkgs.buildPackages.python3}/bin/python3 ${../../scripts/test-openbsd-auth.py} \
      ${config.system.build.vm}/bin/run-${config.system.name}-vm \
      ${pkgs.buildPackages.openssh}/bin/ssh ${askpass} ${pkgs.openbsd.id}/bin/id
  '';
}
