{ inputs, ... }:
{
  perSystem = { pkgs, config, ... }: {
    checks = {
      windows-keybindings-generated = import ./build/windows-keybindings-generated.nix {
        inherit pkgs;
      };
      aerospace-workspace-cycle = import ./build/aerospace-cycle.nix { inherit pkgs; };
      docker-desktop-activation = import ./build/docker-desktop-activation.nix { inherit inputs pkgs; };
      ghostty-config = import ./build/ghostty-config.nix { inherit pkgs; };
      custom-package-builds = import ./build/custom-packages.nix { inherit pkgs; };
      neovim-native = import ./build/neovim.nix { inherit inputs pkgs; };
      hermes-bootstrap-tests = import ./build/hermes-bootstrap-tests.nix { inherit inputs pkgs; };
      hermes-runtime = import ./build/hermes-runtime.nix { inherit inputs pkgs; };
      powershell-formatter = import ./build/powershell-formatter.nix {
        inherit pkgs;
        formatter = config.treefmt.settings.formatter.powershell;
      };
    }
    // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      bootstrap-nixos-vm = import ./build/bootstrap-nixos.nix { inherit inputs pkgs; };
    }
    // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
      standalone-darwin-home = import ./build/standalone-darwin-home.nix {
        inherit inputs pkgs;
      };
    };
    nix-unit.inputs = {
      # Full Darwin activation evaluation needs this nested input in the sandbox.
      "nix-homebrew/brew-src" = inputs.nix-homebrew.inputs.brew-src;
      # Hermes activation also evaluates its locked package input closure.
      "hermes-agent/nixpkgs" = inputs.hermes-agent.inputs.nixpkgs;
      "hermes-agent/flake-parts" = inputs.hermes-agent.inputs.flake-parts;
      "hermes-agent/home-manager" = inputs.hermes-agent.inputs.home-manager;
      "hermes-agent/pyproject-nix" = inputs.hermes-agent.inputs.pyproject-nix;
      "hermes-agent/uv2nix" = inputs.hermes-agent.inputs.uv2nix;
      "hermes-agent/pyproject-build-systems" = inputs.hermes-agent.inputs.pyproject-build-systems;
      "hermes-agent/npm-lockfile-fix" = inputs.hermes-agent.inputs.npm-lockfile-fix;
      # Preserve llm-agents' own dependency graph inside the test sandbox.
      "llm-agents/nixpkgs" = inputs.llm-agents.inputs.nixpkgs;
      "llm-agents/bun2nix" = inputs.llm-agents.inputs.bun2nix;
      "llm-agents/flake-parts" = inputs.llm-agents.inputs.flake-parts;
      "llm-agents/systems" = inputs.llm-agents.inputs.systems;
      "llm-agents/treefmt-nix" = inputs.llm-agents.inputs.treefmt-nix;
      inherit (inputs)
        flake-parts
        home-manager
        hermes-agent
        llm-agents
        nix-darwin
        nix-homebrew
        nix-unit
        nixos-vscode-server
        nixos-wsl
        nixpkgs
        systems
        treefmt-nix
        ;
    };

    nix-unit.tests =
      (import ./unit/home/import-boundary.nix)
      // (import ./unit/home/platform-boundary.nix)
      // (import ./unit/home/composition.nix { inherit inputs; })
      // (import ./unit/home/standalone-darwin-identity.nix { inherit inputs; })
      // (import ./unit/home/rebuild-aliases.nix { inherit inputs; })
      // (import ./unit/ghostty.nix { inherit inputs; })
      // (import ./unit/terminal-tools.nix { inherit inputs; })
      // (import ./unit/font-consistency.nix { inherit inputs; })
      // (import ./unit/darwin-omarchy-keybindings.nix { inherit inputs; })
      // (import ./unit/package-catalog-modularity.nix { inherit inputs; })
      // (import ./unit/keybindings.nix { inherit inputs; })
      // (import ./unit/native-keybindings.nix { inherit inputs; })
      // (import ./unit/windows-keybindings.nix { inherit inputs; })
      // (import ./unit/darwin-package-selection.nix { inherit inputs; })
      // (import ./unit/darwin-hermes-desktop-cask.nix { inherit inputs; })
      // (import ./unit/darwin-vendor-bundles.nix { inherit inputs; })
      // (import ./unit/package-catalog-discord.nix { inherit inputs; })
      // (import ./unit/package-catalog-codex.nix { inherit inputs; })
      // (import ./unit/package-catalog-codex-injection.nix { inherit inputs; })
      // (import ./unit/package-catalog-devcontainers.nix { inherit inputs; })
      // (import ./unit/package-catalog-gcloud.nix { inherit inputs; })
      // (import ./unit/package-catalog-msstore.nix { inherit inputs; })
      // (import ./unit/package-catalog-orca.nix { inherit inputs; })
      // (import ./unit/package-catalog-oxlint-path.nix { inherit inputs; })
      // (import ./unit/package-catalog-provider-coverage.nix { inherit inputs; })
      // (import ./unit/package-catalog-validation-fixtures.nix { inherit inputs; })
      // (import ./unit/package-catalog-desktop-support.nix { inherit inputs; })
      // (import ./unit/package-catalog-darwin-provider-metadata.nix { inherit inputs; })
      // (import ./unit/package-catalog-dia-orca-arc-support.nix { inherit inputs; })
      // (import ./unit/package-catalog-chatgpt-support.nix { inherit inputs; })
      // (import ./unit/package-catalog-docker.nix { inherit inputs; })
      // (import ./unit/package-catalog-docker-custom-provider.nix { inherit inputs; })
      // (import ./unit/package-catalog-gwq.nix { inherit inputs; })
      // (import ./unit/package-catalog-netcat.nix { inherit inputs; })
      // (import ./unit/package-catalog-npm-verifiers.nix { inherit inputs; })
      // (import ./unit/package-catalog-required-provider-reasons.nix { inherit inputs; })
      // (import ./unit/package-catalog-tart.nix { inherit inputs; })
      // (import ./unit/package-catalog-nodejs-selection.nix { inherit inputs; })
      // (import ./unit/package-catalog-windows-only-selection.nix { inherit inputs; })
      // (import ./unit/package-catalog-windows-only-support.nix { inherit inputs; })
      // (import ./unit/package-catalog-windows-path-metadata.nix { inherit inputs; })
      // (import ./unit/package-catalog-windows-cli-verifiers.nix { inherit inputs; })
      // (import ./unit/package-catalog-windows-desktop-verifiers.nix { inherit inputs; })
      // (import ./unit/package-catalog-wsl-verifier.nix { inherit inputs; })
      // (import ./unit/package-catalog-codex-desktop-verifier.nix { inherit inputs; })
      // (import ./unit/package-catalog-wezterm-install-policy.nix { inherit inputs; })
      // (import ./unit/package-catalog-vs-build-tools.nix { inherit inputs; })
      // (import ./unit/package-catalog-wsl.nix { inherit inputs; })
      // (import ./unit/hermes-agent.nix { inherit inputs; })
      // (import ./unit/package-catalog-pnpm.nix { inherit inputs; })
      // (import ./unit/host-package-github-cli.nix { inherit inputs; })
      // (import ./unit/hosts/darwin-layout.nix)
      // (import ./unit/hosts/darwin-configuration.nix { inherit inputs; })
      // (import ./unit/hosts/linux-configuration.nix { inherit inputs; })
      // (import ./unit/hosts/wsl-configuration.nix { inherit inputs; })
      // (import ./unit/flake-outputs.nix { inherit inputs; })
      // (import ./unit/ownership.nix { inherit inputs; });
  };
}
