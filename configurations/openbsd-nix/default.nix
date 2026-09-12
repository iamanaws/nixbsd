# Test openbsd-base's Nix package and daemon with a guest smoke test and archive fixtures.
{ config, pkgs, ... }:
let
  compiler = import ./compiler.nix { inherit pkgs; };
  networkFixtures = pkgs.buildPackages.callPackage ./fixtures.nix { };
  archives =
    pkgs.buildPackages.runCommand "nix-openbsd-test-archives"
      {
        nativeBuildInputs = with pkgs.buildPackages; [
          gnutar
          gzip
          bzip2
          xz
        ];
      }
      ''
        mkdir -p "$out" fixture
        echo 42 > fixture/default.nix
        tar -czf "$out/fixture.tar.gz" fixture
        tar -cjf "$out/fixture.tar.bz2" fixture
        tar -cJf "$out/fixture.tar.xz" fixture
      '';
in
{
  imports = [ ../openbsd-base ];
  security.pki.certificateFiles = [ "${networkFixtures}/cert.pem" ];
  nix.settings.trusted-public-keys = [
    (pkgs.lib.removeSuffix "\n" (builtins.readFile "${networkFixtures}/public-key"))
  ];
  nix.settings.trusted-substituters = [ "https://10.0.2.2:18443/cache" ];
  system.build.nixTestServer = pkgs.buildPackages.writeShellScriptBin "serve-nix-openbsd-fixtures" ''
    exec ${pkgs.buildPackages.python3}/bin/python3 ${../../scripts/serve-nix-openbsd-fixtures.py} ${networkFixtures} "$@"
  '';
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "smoke-test-nix-openbsd" (
      ''
        export NIX_OPENBSD_TEST_VERSION=${config.nix.package.version}
        export NIX_OPENBSD_TEST_SHELL=${pkgs.runtimeShell}
        export NIX_OPENBSD_TEST_ARCHIVES=${archives}
        export NIX_OPENBSD_TEST_NETWORK=${networkFixtures}
        export NIX_OPENBSD_TEST_SLEEP=${pkgs.coreutils}/bin/sleep
        export NIX_OPENBSD_TEST_IFCONFIG=${pkgs.openbsd.ifconfig}/bin/ifconfig
        export NIX_OPENBSD_TEST_COMPILER=${pkgs.lib.getBin compiler}/bin/tcc
        export NIX_OPENBSD_TEST_LIBC=${pkgs.lib.getLib pkgs.stdenv.cc.libc}
        export NIX_OPENBSD_TEST_COREUTILS=${pkgs.coreutils}/bin
        export NIX_OPENBSD_TEST_NATIVE=${./native-build.nix}
      ''
      + builtins.readFile ../../scripts/smoke-test-nix-openbsd.sh
    ))
  ];
  virtualisation.vmVariant.virtualisation.memorySize = 2048;
}
