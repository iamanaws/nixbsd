# Supply the build environment explicitly until OpenBSD has a native stdenv.
{
  shell,
  compiler,
  libc,
  coreutils,
  nonce,
}:
let
  cc = builtins.storePath compiler;
  runtimeLibc = builtins.storePath libc;
in
derivation {
  name = "openbsd-native-c-${nonce}";
  system = "x86_64-openbsd";
  builder = builtins.storePath shell;
  PATH = builtins.storePath coreutils;
  src = builtins.toFile "openbsd-native-c.c" ''
    #include <sys/utsname.h>
    #include <stdio.h>
    #include <string.h>
    #include <unistd.h>

    int main(void) {
        struct utsname host;
        char message[32];
        if (uname(&host) || strcmp(host.sysname, "OpenBSD") || strcmp(host.release, "7.9"))
            return 1;
        if (pledge("stdio", NULL))
            return 2;
        strlcpy(message, "openbsd-native-c-ok", sizeof(message));
        puts(message);
        return 0;
    }
  '';
  args = [
    "-euc"
    ''
      test "$EUID" -ne 0
      mkdir -p "$out/bin"
      ${cc} -v -Wl,-rpath=${runtimeLibc}/lib "$src" -o "$out/bin/openbsd-native-c"
      test "$("$out/bin/openbsd-native-c")" = openbsd-native-c-ok
      echo "$EUID" > "$out/build-uid"
    ''
  ];
}
