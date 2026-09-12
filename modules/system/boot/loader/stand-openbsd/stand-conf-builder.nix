{
  pkgs,
  stand-efi,
  console,
}:

pkgs.replaceVarsWith {
  src = ./stand-conf-builder.sh;
  isExecutable = true;
  replacements = {
    path = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.gnugrep
      pkgs.jq
    ];
    inherit (pkgs) bash;
    stand = stand-efi;
    inherit console;
  };
}
