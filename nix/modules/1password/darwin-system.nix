{ pkgs, ... }:
{
  # Preserve the system app bundle and its existing macOS integration.
  environment.systemPackages = [ pkgs._1password-gui ];
}
