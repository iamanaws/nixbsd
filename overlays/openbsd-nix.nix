# Runtime fixes for guest Nix; keep these separate from package build fixes.
final: prev: {
  nix =
    if prev.stdenv.hostPlatform.isOpenBSD then
      (prev.nix.overrideScope (
        _nixFinal: nixPrev: {
          nix-store = (nixPrev.nix-store.override { withAWS = false; }).overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [
              ./nix-openbsd-builder-pty.patch
              ./nix-openbsd-build-users.patch
            ];
          });
          nix-main = nixPrev.nix-main.overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [ ./nix-openbsd-atfork.patch ];
          });
          nix-util = nixPrev.nix-util.overrideAttrs (old: {
            postPatch = (old.postPatch or "") + ''
              substituteInPlace terminal.cc \
                --replace-fail '#  ifdef __APPLE__' \
                  '#  if defined(__APPLE__) || defined(__OpenBSD__)'
            '';
          });
          nix-cli = nixPrev.nix-cli.overrideAttrs (old: {
            env = (old.env or { }) // {
              NIX_CFLAGS_COMPILE_x86_64_unknown_openbsd =
                (old.env.NIX_CFLAGS_COMPILE_x86_64_unknown_openbsd or "")
                + " -DBOOST_STACKTRACE_GNU_SOURCE_NOT_REQUIRED";
            };
          });
        }
      ))
    else
      prev.nix;
}
