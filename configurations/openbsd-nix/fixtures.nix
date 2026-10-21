{
  runCommand,
  python3,
  nix,
  gitMinimal,
}:
runCommand "nix-openbsd-network-fixtures"
  {
    nativeBuildInputs = [
      (python3.withPackages (p: [ p.cryptography ]))
      nix
      gitMinimal
    ];
  }
  ''
    export NIX_CONFIG='experimental-features = nix-command'
    python3 ${../../scripts/nix-openbsd-fixtures.py} "$out"
  ''
