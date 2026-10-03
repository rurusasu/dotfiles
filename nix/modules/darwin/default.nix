{ pkgs, ... }:
let
  inherit ((import ../fonts.nix { inherit pkgs; })) fonts;
in
{
  # nix-darwin installs fonts; Home Manager configures fontconfig clients.
  fonts.packages = fonts.packages;
  home-manager.sharedModules = [
    # Cursor と Neovim が共用する言語サーバーをユーザー環境へ導入する。
    ../lsp.nix
    ../cursor
    { fonts.fontconfig = fonts.fontconfig; }
  ];
}
