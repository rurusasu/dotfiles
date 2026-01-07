{ inputs, ... }:
{
  imports = [
    inputs.treefmt-nix.flakeModule
    ./hosts.nix
    ./systems.nix
    ./templates.nix
    ./treefmt.nix
  ];
}
