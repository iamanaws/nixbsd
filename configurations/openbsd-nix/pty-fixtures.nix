{ stdenv }:
stdenv.mkDerivation {
  name = "nix-openbsd-pty-fixtures";
  dontUnpack = true;
  buildPhase = ''
    $CC -Wall -Wextra ${./pty-probe.c} -o pty-probe
    $CC -Wall -Wextra -fPIC -shared ${./pty-setup-failure.c} -o setup-failure.so
  '';
  installPhase = ''
    mkdir -p "$out/bin" "$out/lib"
    cp pty-probe "$out/bin/"
    cp setup-failure.so "$out/lib/"
  '';
}
