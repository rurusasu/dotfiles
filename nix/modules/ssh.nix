{ pkgs, ... }:
{
  programs.ssh = {
    enable = true;
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
}
