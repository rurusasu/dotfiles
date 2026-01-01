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

  nix.nixPath = [
    "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"
    "nixos-config=/etc/nixos/configuration.nix"
  ];
}
