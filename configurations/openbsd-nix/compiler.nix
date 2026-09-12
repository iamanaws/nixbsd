{ pkgs }:

# A small compiler for native build tests, cross-built with the image.
pkgs.tinycc.overrideAttrs (old: {
  configureFlags = builtins.filter (flag: flag != "--enable-cross") old.configureFlags ++ [
    "--targetos=OpenBSD"
    "--config-bcheck=no"
    "--config-backtrace=no"
  ];
  makeFlags = (old.makeFlags or [ ]) ++ [ "x86_64-libtcc1-usegcc=yes" ];
  postPatch = old.postPatch + ''
    substituteInPlace Makefile \
      --replace-fail '$(CC) -DC2STR' '${pkgs.buildPackages.stdenv.cc}/bin/cc -DC2STR'
  '';
})
