{ inputs, ... }:
{
  perSystem = { pkgs, ... }: {
    checks.ghostty-config =
      pkgs.runCommand "ghostty-config-check"
        {
          nativeBuildInputs = [
            pkgs.bats
            pkgs.chezmoi
          ];
        }
        ''
          export HOME="$TMPDIR/home"
          export GHOSTTY_TEST_REPO_ROOT=${../..}
          mkdir -p "$HOME"
          bats ${../../tests/bash/ghostty_config.bats}
          touch "$out"
        '';
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
      # nix-unit evaluates the nested llm-agents input in its isolated builder.
      "llm-agents/nixpkgs" = inputs.nixpkgs;
    };

    nix-unit.tests =
      (import ../tests/home/import-boundary.nix)
      // (import ../tests/home/platform-boundary.nix)
      // (import ../tests/home/composition.nix { inherit inputs; })
      // (import ../tests/ghostty.nix { inherit inputs; })
      // (import ../tests/hosts/darwin-layout.nix)
      // (import ../tests/hosts/darwin-configuration.nix { inherit inputs; })
      // (import ../tests/flake-outputs.nix)
      // (import ../tests/ownership.nix);
  };
}
