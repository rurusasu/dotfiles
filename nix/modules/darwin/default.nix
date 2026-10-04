{ pkgs, ... }:
let
  inherit ((import ../fonts.nix { inherit pkgs; })) fonts;
in
{
  programs.zsh.enable = true;

  # nix-darwin installs fonts; Home Manager configures fontconfig clients.
  fonts.packages = fonts.packages;
  home-manager.sharedModules = [
    ../shells/zsh
    ./ghostty.nix
    ./wezterm.nix
    ../terminals/ghostty/defaults.nix
    ../terminals/wezterm/defaults.nix
    # Neovim が利用する言語サーバーをユーザー環境へ導入する。
    ../lsp.nix
    { fonts.fontconfig = fonts.fontconfig; }
  ];
}
