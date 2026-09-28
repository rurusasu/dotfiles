# Package identities and provider declarations for core.
{ pkgs, ... }:
{
  chezmoi = {
    pkg = pkgs.chezmoi;
    winget = "twpayne.chezmoi";
    category = "core";
  };

  git = {
    pkg = pkgs.git;
    winget = "Git.Git";
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

  ripgrep = {
    pkg = pkgs.ripgrep;
    winget = "BurntSushi.ripgrep.MSVC";
    category = "core";
  };

  bat = {
    pkg = pkgs.bat;
    winget = null;
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

  eza = {
    pkg = pkgs.eza;
    winget = "eza-community.eza";
    category = "core";
  };

  zoxide = {
    pkg = pkgs.zoxide;
    winget = "ajeetdsouza.zoxide";
    category = "core";
  };

  fzf = {
    pkg = pkgs.fzf;
    winget = "junegunn.fzf";
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
