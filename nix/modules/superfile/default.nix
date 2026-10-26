{ config, lib, ... }:
{
  programs.superfile = {
    enable = true;
    settings = {
      theme = "catppuccin-mocha";
      editor = "nvim";
      default_open_file_preview = true;
      nerdfont = true;
    };
  };

  # nixpkgs provides `superfile`; keep the documented `spf` command on WSL too.
  home.file.".local/bin/spf".source = lib.getExe config.programs.superfile.package;
}
