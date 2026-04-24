{ inputs, ... }:
{
  imports = [
    inputs.treefmt-nix.flakeModule
    ./home.nix
    ./hosts.nix
    ./packages.nix
    ./systems.nix
    ./templates.nix
    ./treefmt.nix
  ];
}
