{ lib, pkgs, ... }:
{
  imports = [ ./ssh.nix ];

  # The pinned Home Manager has no dedicated 1Password program module.
  # Keep the existing Linux desktop installation; nix-darwin owns the macOS app.
  home.packages = [
    pkgs._1password-cli
  ]
  ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs._1password-gui ];
}
