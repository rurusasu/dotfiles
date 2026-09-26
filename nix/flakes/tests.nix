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
        hermes-agent
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
      // (import ../tests/home/rebuild-aliases.nix { inherit inputs; })
      // (import ../tests/ghostty.nix { inherit inputs; })
      // (import ../tests/darwin-package-selection.nix { inherit inputs; })
      // (import ../tests/darwin-hermes-desktop-cask.nix { inherit inputs; })
      // (import ../tests/darwin-provider-candidates.nix)
      // (import ../tests/darwin-vendor-bundles.nix { inherit inputs; })
      // (import ../tests/package-catalog-discord.nix { inherit inputs; })
      // (import ../tests/package-catalog-codex.nix { inherit inputs; })
      // (import ../tests/package-catalog-codex-injection.nix { inherit inputs; })
      // (import ../tests/package-catalog-hermes-default-output.nix { inherit inputs; })
      // (import ../tests/package-catalog-devcontainers.nix { inherit inputs; })
      // (import ../tests/package-catalog-gcloud.nix { inherit inputs; })
      // (import ../tests/package-catalog-msstore.nix { inherit inputs; })
      // (import ../tests/package-catalog-orca.nix { inherit inputs; })
      // (import ../tests/package-catalog-oxlint-path.nix { inherit inputs; })
      // (import ../tests/package-catalog-provider-coverage.nix { inherit inputs; })
      // (import ../tests/package-catalog-validation-fixtures.nix { inherit inputs; })
      // (import ../tests/package-catalog-claude-tableplus-absence.nix { inherit inputs; })
      // (import ../tests/package-catalog-desktop-support.nix { inherit inputs; })
      // (import ../tests/package-catalog-darwin-migration-metadata.nix { inherit inputs; })
      // (import ../tests/package-catalog-dia-orca-arc-support.nix { inherit inputs; })
      // (import ../tests/package-catalog-chatgpt-support.nix { inherit inputs; })
      // (import ../tests/package-catalog-docker.nix { inherit inputs; })
      // (import ../tests/package-catalog-docker-custom-provider.nix { inherit inputs; })
      // (import ../tests/package-catalog-gwq.nix { inherit inputs; })
      // (import ../tests/package-catalog-herdr-absence.nix { inherit inputs; })
      // (import ../tests/package-catalog-netcat.nix { inherit inputs; })
      // (import ../tests/package-catalog-npm-verifiers.nix { inherit inputs; })
      // (import ../tests/package-catalog-ollama-windows-policy.nix { inherit inputs; })
      // (import ../tests/package-catalog-playwright-feature.nix { inherit inputs; })
      // (import ../tests/package-catalog-required-provider-reasons.nix { inherit inputs; })
      // (import ../tests/package-catalog-tart-minimal.nix { inherit inputs; })
      // (import ../tests/package-catalog-nodejs-selection.nix { inherit inputs; })
      // (import ../tests/package-catalog-windows-only-selection.nix { inherit inputs; })
      // (import ../tests/package-catalog-windows-only-support.nix { inherit inputs; })
      // (import ../tests/package-catalog-retired-identifiers.nix { inherit inputs; })
      // (import ../tests/package-catalog-windows-path-metadata.nix { inherit inputs; })
      // (import ../tests/package-catalog-windows-cli-verifiers.nix { inherit inputs; })
      // (import ../tests/package-catalog-windows-desktop-verifiers.nix { inherit inputs; })
      // (import ../tests/package-catalog-wsl-verifier.nix { inherit inputs; })
      // (import ../tests/package-catalog-codex-desktop-verifier.nix { inherit inputs; })
      // (import ../tests/package-catalog-wezterm-install-policy.nix { inherit inputs; })
      // (import ../tests/package-catalog-vs-build-tools.nix { inherit inputs; })
      // (import ../tests/package-catalog-wsl.nix { inherit inputs; })
      // (import ../tests/system-manager-host-contracts.nix { inherit inputs; })
      // (import ../tests/system-manager-docker-config.nix { inherit inputs; })
      // (import ../tests/system-manager-user-identity.nix { inherit inputs; })
      // (import ../tests/system-manager-integrations.nix { inherit inputs; })
      // (import ../tests/hermes-docker.nix { inherit inputs; })
      // (import ../tests/hermes-agent.nix { inherit inputs; })
      // (import ../tests/chatgpt-linux.nix { inherit inputs; })
      // (import ../tests/package-catalog-pnpm.nix { inherit inputs; })
      // (import ../tests/package-catalog-warp.nix { inherit inputs; })
      // (import ../tests/host-package-github-cli.nix { inherit inputs; })
      // (import ../tests/hosts/darwin-layout.nix)
      // (import ../tests/hosts/darwin-configuration.nix { inherit inputs; })
      // (import ../tests/hosts/wsl-configuration.nix { inherit inputs; })
      // (import ../tests/flake-outputs.nix)
      // (import ../tests/ownership.nix { inherit inputs; });
  };
}
