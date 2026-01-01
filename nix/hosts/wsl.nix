{ config, pkgs, ... }:
{
  # WSL-specific system settings can go here.
  # Docker is handled by Docker Desktop on Windows.
  environment.systemPackages = [
    pkgs.coreutils
  ];

  system.activationScripts.wslWhoami = {
    text = ''
      ln -sf /run/current-system/sw/bin/whoami /bin/whoami
      ln -sf /run/current-system/sw/bin/whoami /usr/bin/whoami
    '';
  };
}
