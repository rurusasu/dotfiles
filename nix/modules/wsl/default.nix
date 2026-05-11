{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    coreutils
    # Japanese input: fcitx5+mozc installed as system packages.
    # i18n.inputMethod is intentionally NOT used here because it auto-generates
    # app-org.fcitx.Fcitx5@autostart.service, which conflicts with the Home Manager
    # user systemd service that runs fcitx5 with --disable=wayland (required for WSLg).
    fcitx5
    fcitx5-mozc
    fcitx5-gtk
  ];

  # Merge /share/fcitx5 from all installed packages into /run/current-system/sw/share/fcitx5.
  # Without this, fcitx5 cannot find addon/inputmethod conf files provided by
  # separate packages like fcitx5-mozc (only the fcitx5 package itself is searched by default).
  environment.pathsToLink = [ "/share/fcitx5" ];

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

  # PAM integration for gnome-keyring: auto-unlocks the keyring on login when a
  # proper PAM session is used. The daemon itself is started by a Home Manager
  # user systemd service (see nix/home/wsl/users.nix) to avoid a duplicate
  # instance competing for the org.freedesktop.secrets D-Bus name.
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
