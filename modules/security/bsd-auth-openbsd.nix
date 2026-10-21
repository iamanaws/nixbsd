{
  config,
  lib,
  pkgs,
  ...
}:
{
  users.classes = {
    auth-defaults.settings.auth = lib.mkDefault "passwd,skey";
    auth-ftp-defaults.settings.auth-ftp = lib.mkDefault "passwd";
    default.settings = {
      auth = lib.mkDefault "passwd";
      auth-ftp = lib.mkDefault "passwd";
    };
  };

  security.wrappers.login_passwd = {
    setuid = true;
    owner = "root";
    group = "wheel";
    permissions = "u+rx,g+rx,o+rx";
    source = "${pkgs.openbsd.login_passwd}/bin/login_passwd";
  };

  # BSD authentication uses a fixed helper path, independent of getty or su.
  system.activationScripts.bsd-auth = {
    deps = [ "usrbinenv" ];
    text = ''
      mkdir -p /usr/libexec/auth
      ln -sfn ${config.security.wrapperDir}/login_passwd /usr/libexec/auth/login_passwd
    '';
  };
}
