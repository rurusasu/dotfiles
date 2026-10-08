{ pkgs, ... }:
let
  inherit ((import ../../modules/fonts.nix { inherit pkgs; })) fonts;
in
{
  programs.gnupg.agent.enableSSHSupport = false;
  programs.zsh = {
    enable = true;
    # Home Manager の zsh-autocomplete に補完初期化を任せる。
    enableGlobalCompInit = false;
  };

  # nix-darwin installs fonts; nix/hosts/aarch64-darwin/home.nix configures fontconfig clients.
  fonts.packages = fonts.packages;
  home-manager.sharedModules = [
    ../../modules/shells/zsh
    ./ghostty.nix
    ./wezterm.nix
    ../../modules/terminals/ghostty/defaults.nix
    ../../modules/terminals/wezterm/defaults.nix
    # Neovim が利用する言語サーバーをユーザー環境へ導入する。
    ../../modules/lsp.nix
  ];
}
