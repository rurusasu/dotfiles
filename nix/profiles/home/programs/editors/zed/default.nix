{ pkgs, lib, ... }:
{
  # Zed editor
  # Settings are managed by chezmoi (editors/zed/)
  home.packages = with pkgs; [
    zed-editor
  ];
}
