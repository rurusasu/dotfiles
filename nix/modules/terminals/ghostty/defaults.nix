{ config, lib, ... }:
let
  allocation = import ../../../home/keybindings/bindings.nix { inherit lib; };
  fromWindowsExport = lib.attrByPath [ "dotfiles" "keybindings" "fromWindowsExport" ] false config;
  keybindConfig =
    if fromWindowsExport then
      "config-file = ?${config.xdg.configHome}/dotfiles/keybindings/ghostty.conf\n"
    else
      allocation.ghosttyConfig;
in
{
  imports = [ (import ../../tools.nix).ghostty ];
  programs.ghostty = {
    settings = { };
    enableBashIntegration = true;
    enableFishIntegration = false;
    enableZshIntegration = true;
    installBatSyntax = false;
  };

  xdg.configFile."ghostty/config" = {
    # WSL loads chezmoi's exported data; native Unix embeds the same renderer output.
    # Keep Ghostty defaults, including macOS Command bindings.
    text = builtins.readFile ./config.ghostty + "\n" + keybindConfig;
    onChange = "${config.programs.ghostty.package}/bin/ghostty +validate-config --config-file=${config.xdg.configHome}/ghostty/config";
  };
}
