# Package identities and provider declarations for core.
{ pkgs, ... }:
{
  chezmoi = {
    pkg = pkgs.chezmoi;
    winget = "twpayne.chezmoi";
    category = "core";
  };

  gh = {
    pkg = pkgs.gh;
    winget = "GitHub.cli";
    category = "core";
  };

  fd = {
    pkg = pkgs.fd;
    winget = "sharkdp.fd";
    category = "core";
  };

  jq = {
    pkg = pkgs.jq;
    winget = "jqlang.jq";
    category = "core";
  };

  netcat = {
    pkg = pkgs.netcat;
    winget = null;
    category = "core";
  };

  direnv = {
    pkg = pkgs.direnv;
    winget = "direnv.direnv";
    category = "core";
  };

  unzip = {
    pkg = pkgs.unzip;
    winget = null;
    category = "core";
  };

  p7zip = {
    pkg = pkgs.p7zip;
    winget = null;
    category = "core";
  };
}
