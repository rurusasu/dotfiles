{ ... }:
{
  system.stateVersion = "25.05";

  # Boot — override per machine
  boot.loader.grub.devices = [ "/dev/sda" ];
  fileSystems."/" = {
    device = "/dev/sda1";
    fsType = "ext4";
  };

  # User
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "docker"
    ];
  };
  users.groups.nixos = { };

  virtualisation.docker = {
    enable = true;
    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };
}
