{
  rustPlatform,
  lib,
  fetchFromGitHub,
  ...
}:
rustPlatform.buildRustPackage (final: {
  name = "mini-tmpfiles";
  version = "0.1.0";
  src = fetchFromGitHub {
    owner = "nixos-bsd";
    repo = "mini-tmpfiles";
    tag = "v${final.version}";
    hash = "sha256-rmrAK/K6l2LTZhDHyJZzOA4Rr/l/ibfCfFLeilgGLpU=";
  };

  cargoHash = "sha256-KcKgz5Q3YMIjFnv9IQTaMBKfJQXKiibV5kH4E5yug+E=";

  meta = {
    homepage = "https://github.com/nixos-bsd/mini-tmpfiles";
    description = "Standalone replacement for systemd-tmpfiles";
    maintainers = with lib.maintainers; [ artemist ];
    license = with lib.licenses; [ mit ];
    platforms = lib.platforms.unix;
  };
})
