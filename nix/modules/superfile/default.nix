{ config, lib, ... }:
{
  config = lib.mkIf config.programs.superfile.enable {
    programs.superfile = {
      settings = {
        # Home Manager writes a partial config; use superfile defaults for the rest.
        ignore_missing_fields = true;
        theme = "catppuccin-${config.catppuccin.flavor}";
        editor = "nvim";
      };
    };

    # nixpkgs provides `superfile`; keep the documented `spf` command on WSL too.
    home.file.".local/bin/spf".source = lib.getExe config.programs.superfile.package;
  };
}
