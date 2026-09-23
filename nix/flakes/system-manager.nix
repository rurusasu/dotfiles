{ inputs, ... }:
{
  flake.systemConfigs = import ./lib/system-manager-configs.nix { inherit inputs; };
}
