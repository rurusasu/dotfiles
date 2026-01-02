{ config, pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.coreutils
  ];

  system.activationScripts.wslWhoami = {
    text = ''
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

  nix.nixPath = [
    "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"
    "nixos-config=/etc/nixos/configuration.nix"
  ];
}
