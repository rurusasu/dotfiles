{ config, pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.coreutils
  ];

  system.activationScripts.wslWhoami = {
    text = ''
      mkdir -p /usr/bin
      ln -sf /run/current-system/sw/bin/whoami /bin/whoami
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
    ];
  };

  # WSL のデフォルトでは /etc/hosts を毎回上書きするため generateHosts = false で無効化し、
  # NixOS が networking.extraHosts 経由で /etc/hosts を管理できるようにする。
  wsl.wslConf.network.generateHosts = false;

  # Ensure nix-ld works for non-login shells (e.g. VS Code WSL server).
  environment.variables = {
    NIX_LD = "/run/current-system/sw/share/nix-ld/lib/ld.so";
    NIX_LD_LIBRARY_PATH = "/run/current-system/sw/share/nix-ld/lib";
  };
}
