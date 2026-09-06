{ inputs, ... }:
{
  perSystem = {
    nix-unit.inputs = {
      inherit (inputs)
        flake-parts
        home-manager
        llm-agents
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

    nix-unit.tests =
      (import ../tests/home/import-boundary.nix)
      // (import ../tests/home/platform-boundary.nix)
      // (import ../tests/home/composition.nix { inherit inputs; })
      // (import ../tests/hosts/darwin-layout.nix)
      // (import ../tests/hosts/darwin-configuration.nix { inherit inputs; })
      // (import ../tests/flake-outputs.nix)
      // (import ../tests/ownership.nix);
  };
}
