{ pkgs, ... }:
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
    # Extensions are managed by chezmoi (editors/vscode/extensions.json)
    # Set to true to allow chezmoi deployment scripts to install extensions
    mutableExtensionsDir = true;
    # settings.json, keybindings.json, extensions are managed by chezmoi
  };
}
