{ pkgs, lib, ... }:
{
  # Cursor is not available in nixpkgs
  # On NixOS/Linux: Install via AppImage or other methods
  # On Windows: Install via winget (winget install Anysphere.Cursor)
  # Settings are managed by chezmoi (editors/cursor/)

  # Note: If cursor becomes available in nixpkgs, enable this:
  # home.packages = [ pkgs.cursor ];
}
