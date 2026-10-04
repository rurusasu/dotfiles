{ inputs, pkgs, ... }:
{
  imports = [
    ../fonts.nix
    inputs.home-manager.nixosModules.home-manager
  ];

  nixpkgs.config.allowUnfree = true;
  programs.zsh.enable = true;
  fonts.fontDir.enable = true;

  # WSL の per-user profile にも言語サーバーを公開する。
  home-manager.sharedModules = [
    ./ghostty.nix
    ../terminals/ghostty/defaults.nix
    ../terminals/wezterm/defaults.nix
    ../lsp.nix
  ];
}
