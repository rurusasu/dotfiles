{
  config,
  lib,
  pkgs,
  ...
}:
let
  appearance = import ../appearance.nix;
in
{
  config = lib.mkIf config.programs.ghostty.enable {
    programs.ghostty = {
      package = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin pkgs.ghostty-bin;
      systemd.enable = pkgs.stdenv.hostPlatform.isLinux;
      settings = {
        inherit (appearance) theme;
        font-family = appearance.font_family;
        font-size = appearance.font_size;
        macos-option-as-alt = true;
        keybind = import ./ghostty.nix;
      };
      enableBashIntegration = true;
      enableFishIntegration = false;
      enableZshIntegration = true;
      installBatSyntax = false;
    };
  };
}
