{ inputs, ... }:
{
  perSystem = {
    nix-unit.inputs = {
      inherit (inputs)
        flake-parts
        home-manager
        nix-darwin
        nix-homebrew
        nix-unit
        nixos-vscode-server
        nixos-wsl
        nixpkgs
        system-manager
        systems
        treefmt-nix
        workmux
        ;
    };

    nix-unit.tests = import ../tests/home/import-boundary.nix;
  };
}
