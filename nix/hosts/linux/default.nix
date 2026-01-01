{ config, pkgs, ... }:
{
  imports = [
    ../../modules/host
  ];

  virtualisation.docker = {
    enable = true;
    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };
}
