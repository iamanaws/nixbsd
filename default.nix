{
  nixpkgs ? <nixpkgs>,
  configuration ?
    let
      e = builtins.getEnv "NIXOS_CONFIG";
    in
    if e != "" then e else <nixos-config>,
  system ? builtins.currentSystem,
  # This should only be used for special arguments that need to be evaluated when resolving module structure (like in imports).
  # For everything else, there's _module.args.
  specialArgs ? { },
}:

let
  lib = (import "${nixpkgs}/lib");

  eval = import ./lib/eval-config.nix {
    inherit system specialArgs;
    lib = import "${nixpkgs}/lib";
    nixpkgsPath = nixpkgs;
    modules = [ configuration ];
  };

in

{
  inherit (eval) pkgs config options;

  system = eval.config.system.build.toplevel;

  inherit (eval.config.system.build) vm vmWithBootLoader;
}
