{ inputs, pkgs, ... }:
{
  imports = [
    ../fonts.nix
    inputs.home-manager.nixosModules.home-manager
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = true;
  programs.zsh = {
    enable = true;
    # Home Manager の zsh-autocomplete に補完初期化を任せる。
    enableGlobalCompInit = false;
  };
  fonts.fontDir.enable = true;

  # WSL の per-user profile にも言語サーバーを公開する。
  home-manager.sharedModules = [
    ../shells/zsh
    ./ghostty.nix
    ../terminals/ghostty/defaults.nix
    ../terminals/wezterm/defaults.nix
    ../lsp.nix
  ];
}
