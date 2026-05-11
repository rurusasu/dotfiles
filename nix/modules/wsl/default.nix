{ config, pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.coreutils
  ];

  system.activationScripts.wslWhoami = {
    text = ''
      mkdir -p /usr/bin
      ln -sf /run/current-system/sw/bin/whoami /usr/bin/whoami
    '';
  };

  # Allow running dynamically linked binaries in WSL (e.g. VS Code Server).
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc
      zlib
      openssl
      wayland
      libxkbcommon
    ];
  };

  # Secret Service for Warp (and other apps) to persist credentials across restarts.
  # Without this, Warp shows "Failed to acquire default Secret Service collection".
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.login.enableGnomeKeyring = true;

  # XDG desktop portal: provides color-scheme and other settings queries via D-Bus.
  # Without this, Warp logs "XDG Settings Portal did not return response in time".
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "*";
  };

  # Re-register WSLInterop binfmt entry after systemd clears it on boot.
  # Without this, Windows .exe files (e.g. VS Code) cannot be executed from WSL.
  wsl.interop.register = true;

  # WSL のデフォルトでは /etc/hosts を毎回上書きするため generateHosts = false で無効化し、
  # NixOS が networking.extraHosts 経由で /etc/hosts を管理できるようにする。
  wsl.wslConf.network.generateHosts = false;

  # Ensure nix-ld works for non-login shells (e.g. VS Code WSL server).
  environment.variables = {
    NIX_LD = "/run/current-system/sw/share/nix-ld/lib/ld.so";
    NIX_LD_LIBRARY_PATH = "/run/current-system/sw/share/nix-ld/lib";
    WARP_ENABLE_WAYLAND = "1";
  };
}
