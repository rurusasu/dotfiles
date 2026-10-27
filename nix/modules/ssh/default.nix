{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.programs.ssh.enable {
    programs.ssh = {
      package = pkgs.openssh;
      enableDefaultConfig = false;
      includes = [ "~/.ssh/orca-docker-*.config" ];
      settings."github.com" = {
        HostName = "github.com";
        User = "git";
        IdentityFile = "~/.ssh/signing_key.pub";
        IdentitiesOnly = true;
      };
    };
    home.file.".ssh/config".force = true;
  };
}
