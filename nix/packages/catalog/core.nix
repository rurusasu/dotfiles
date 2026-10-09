# Package identities and provider declarations for core.
{ pkgs, ... }:
{
  chezmoi = {
    winget = "twpayne.chezmoi";
    category = "core";
    support = {
      windows = {
        provider = "winget";
        source = "winget";
        identity = "twpayne.chezmoi";
      };
      darwin.unsupported = "Home Manager owns Unix configuration";
      linux.unsupported = "Home Manager owns Unix configuration";
    };
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
