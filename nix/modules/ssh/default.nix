{
  config,
  lib,
  pkgs,
  ...
}:
let
  homePath = suffix: ''"${lib.escape [ "\\" "\"" ] (config.home.homeDirectory + suffix)}"'';
in
{
  config = lib.mkIf config.programs.ssh.enable {
    programs.ssh = {
      package = pkgs.openssh;
      enableDefaultConfig = false;
      includes = [ (homePath "/.ssh/orca-docker-*.config") ];
      settings."github.com" = {
        HostName = "github.com";
        User = "git";
        IdentityFile = homePath "/.ssh/signing_key.pub";
        IdentitiesOnly = true;
      };
    };
    home.file.".ssh/config".force = true;
  };
}
