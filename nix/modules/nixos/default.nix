{ inputs, ... }:
{
  imports = [
    ../fonts.nix
    inputs.home-manager.nixosModules.home-manager
  ];

  fonts.fontDir.enable = true;

  # WSL の per-user profile にも言語サーバーを公開する。
  home-manager.sharedModules = [
    ../lsp.nix
    ../cursor
  ];
}
