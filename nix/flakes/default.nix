{ inputs, ... }:
{
  imports = [
    inputs.nix-unit.modules.flake.default
    inputs.treefmt-nix.flakeModule
    ./apps.nix
    ./darwin.nix
    ./home.nix
    ./hosts.nix
    ./packages.nix
    ./system-manager.nix
    ./systems.nix
    ./tests.nix
    ./treefmt.nix
  ];
}
