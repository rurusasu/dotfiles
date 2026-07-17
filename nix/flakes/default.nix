{ inputs, ... }:
{
  imports = [
    inputs.treefmt-nix.flakeModule
    ./apps.nix
    ./darwin.nix
    ./home.nix
    ./hosts.nix
    ./packages.nix
    ./system-manager.nix
    ./systems.nix
    ./treefmt.nix
  ];
}
