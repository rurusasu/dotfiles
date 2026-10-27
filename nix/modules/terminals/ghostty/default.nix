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
      }
      // (
        if lib.attrByPath [ "dotfiles" "keybindings" "fromWindowsExport" ] false config then
          # WSL loads chezmoi's optional export; native Unix uses the shared key allocation.
          { config-file = "?${config.xdg.configHome}/dotfiles/keybindings/ghostty.conf"; }
        else
          {
            keybind = import ./ghostty-renderer.nix {
              inherit lib;
              bindings = (import ../../../home/keybindings/bindings.nix { inherit lib; }).ghostty;
              asList = true;
            };
          }
      );
      enableBashIntegration = true;
      enableFishIntegration = false;
      enableZshIntegration = true;
      installBatSyntax = false;
    };
  };
}
