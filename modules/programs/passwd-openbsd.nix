{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.programs.passwd.enable = lib.mkEnableOption "the utility for changing passwords" // {
    default = true;
  };

  config = lib.mkIf config.programs.passwd.enable {
    security.wrappers.passwd = {
      setuid = true;
      owner = "root";
      group = "root";
      source = lib.getExe pkgs.openbsd.passwd;
    };

    # libutil's pw_mkdb and passwd's unveil list use this fixed path.
    system.activationScripts.passwd-mkdb = {
      deps = [ "usrbinenv" ];
      text = ''
        mkdir -p /usr/sbin
        ln -sfn ${lib.getExe' pkgs.openbsd.pwd_mkdb "pwd_mkdb"} /usr/sbin/pwd_mkdb
      '';
    };
  };
}
