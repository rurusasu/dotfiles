{ inputs, ... }:
{
  imports = [
    inputs.treefmt-nix.flakeModule
    ./hosts.nix
    ./packages.nix
    ./systems.nix
    ./templates.nix
    ./treefmt.nix
  ];
}
