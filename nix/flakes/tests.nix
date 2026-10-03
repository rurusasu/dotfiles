{ inputs, ... }:
{
  perSystem = { pkgs, ... }: {
    checks = {
      windows-keybindings-generated = import ../tests/build/windows-keybindings-generated.nix {
        inherit pkgs;
      };
      aerospace-workspace-cycle = import ../tests/build/aerospace-cycle.nix { inherit pkgs; };
      ghostty-config = import ../tests/build/ghostty-config.nix { inherit pkgs; };
      custom-package-builds = import ../tests/build/custom-packages.nix { inherit pkgs; };
      neovim-native = import ../tests/build/neovim.nix { inherit inputs pkgs; };
      hermes-bootstrap-tests = import ../tests/build/hermes-bootstrap-tests.nix { inherit inputs pkgs; };
    }
    // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      bootstrap-nixos-vm = import ../tests/build/bootstrap-nixos.nix { inherit inputs pkgs; };
    }
    // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
      standalone-darwin-home = import ../tests/build/standalone-darwin-home.nix {
        inherit inputs pkgs;
      };
    };
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
      (import ../tests/unit/home/import-boundary.nix)
      // (import ../tests/unit/home/platform-boundary.nix)
      // (import ../tests/unit/home/composition.nix { inherit inputs; })
      // (import ../tests/unit/home/standalone-darwin-identity.nix { inherit inputs; })
      // (import ../tests/unit/home/rebuild-aliases.nix { inherit inputs; })
      // (import ../tests/unit/ghostty.nix { inherit inputs; })
      // (import ../tests/unit/font-consistency.nix { inherit inputs; })
      // (import ../tests/unit/darwin-omarchy-keybindings.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-modularity.nix { inherit inputs; })
      // (import ../tests/unit/keybindings.nix { inherit inputs; })
      // (import ../tests/unit/native-keybindings.nix { inherit inputs; })
      // (import ../tests/unit/windows-keybindings.nix { inherit inputs; })
      // (import ../tests/unit/darwin-package-selection.nix { inherit inputs; })
      // (import ../tests/unit/darwin-hermes-desktop-cask.nix { inherit inputs; })
      // (import ../tests/unit/darwin-provider-candidates.nix)
      // (import ../tests/unit/darwin-vendor-bundles.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-discord.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-codex.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-codex-injection.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-hermes-default-output.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-devcontainers.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-gcloud.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-msstore.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-orca.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-oxlint-path.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-provider-coverage.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-validation-fixtures.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-claude-tableplus-absence.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-desktop-support.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-darwin-migration-metadata.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-dia-orca-arc-support.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-chatgpt-support.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-docker.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-docker-custom-provider.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-gwq.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-herdr-absence.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-netcat.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-npm-verifiers.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-ollama-windows-policy.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-playwright-feature.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-required-provider-reasons.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-tart.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-nodejs-selection.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-windows-only-selection.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-windows-only-support.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-retired-identifiers.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-windows-path-metadata.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-windows-cli-verifiers.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-windows-desktop-verifiers.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-wsl-verifier.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-codex-desktop-verifier.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-wezterm-install-policy.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-vs-build-tools.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-wsl.nix { inherit inputs; })
      // (import ../tests/unit/system-manager-host-contracts.nix { inherit inputs; })
      // (import ../tests/unit/system-manager-docker-config.nix { inherit inputs; })
      // (import ../tests/unit/system-manager-user-identity.nix { inherit inputs; })
      // (import ../tests/unit/system-manager-integrations.nix { inherit inputs; })
      // (import ../tests/unit/hermes-docker.nix { inherit inputs; })
      // (import ../tests/unit/hermes-agent.nix { inherit inputs; })
      // (import ../tests/unit/chatgpt-linux.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-pnpm.nix { inherit inputs; })
      // (import ../tests/unit/package-catalog-warp.nix { inherit inputs; })
      // (import ../tests/unit/host-package-github-cli.nix { inherit inputs; })
      // (import ../tests/unit/hosts/darwin-layout.nix)
      // (import ../tests/unit/hosts/darwin-configuration.nix { inherit inputs; })
      // (import ../tests/unit/hosts/wsl-configuration.nix { inherit inputs; })
      // (import ../tests/unit/flake-outputs.nix)
      // (import ../tests/unit/ownership.nix { inherit inputs; });
  };
}
