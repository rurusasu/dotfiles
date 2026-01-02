{ inputs, ... }: {
  imports = [
    inputs.treefmt-nix.flakeModule
    ./hosts.nix
    ./systems.nix
    ./treefmt.nix
  ];
}
