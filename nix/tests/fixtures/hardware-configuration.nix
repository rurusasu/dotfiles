_: {
  boot.loader.grub.enable = false;
  fileSystems."/" = {
    device = "/dev/vda1";
    fsType = "ext4";
  };

  # This profile exists only for evaluation/build CI. Real machines always use
  # their own /etc/nixos/hardware-configuration.nix through install.sh.
  security.sudo.wheelNeedsPassword = false;
  environment.etc."nixos/hardware-configuration.nix".source = ./hardware-configuration.nix;
}
