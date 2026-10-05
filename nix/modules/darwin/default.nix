{ pkgs, ... }:
let
  inherit ((import ../fonts.nix { inherit pkgs; })) fonts;
in
{
  programs.zsh = {
    enable = true;
    # Home Manager の zsh-autocomplete に補完初期化を任せる。
    enableGlobalCompInit = false;
  };

  # nix-darwin installs fonts; nix/home/darwin.nix configures fontconfig clients.
  fonts.packages = fonts.packages;
  home-manager.sharedModules = [
    ../shells/zsh
    ./ghostty.nix
    ./wezterm.nix
    ../terminals/ghostty/defaults.nix
    ../terminals/wezterm/defaults.nix
    # Neovim が利用する言語サーバーをユーザー環境へ導入する。
    ../lsp.nix
  ];
}
