{ inputs, ... }:
{
  perSystem = { pkgs, config, ... }: {
    checks = {
      aerospace-workspace-cycle = import ./build/aerospace-cycle.nix { inherit pkgs; };
      docker-desktop-activation = import ./build/docker-desktop-activation.nix { inherit inputs pkgs; };
      wezterm-config = import ./build/wezterm-config.nix { inherit inputs pkgs; };
      custom-package-builds = import ./build/custom-packages.nix {
        inherit pkgs;
        chatgptDesktopCheck = config.checks.chatgpt-desktop or null;
      };
      neovim-native = import ./build/neovim.nix { inherit inputs pkgs; };
      powershell-formatter = import ./build/powershell-formatter.nix {
        inherit pkgs;
        formatter = config.treefmt.settings.formatter.powershell;
      };
      chatgpt-desktop = import ./build/chatgpt-desktop.nix { inherit inputs pkgs; };
      hermes-configuration = import ./build/hermes-configuration.nix { inherit pkgs; };
    }
    // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
      darwin-bundled-app-cleanup = import ./build/darwin-bundled-app-cleanup.nix { inherit pkgs; };
      hermes-bundled = import ./build/hermes-bundled.nix { inherit inputs pkgs; };
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
        chatgpt-nixpkgs
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
      // (import ./unit/home/starship.nix { inherit inputs; })
      // (import ./unit/home/standalone-darwin-identity.nix { inherit inputs; })
      // (import ./unit/home/rebuild-aliases.nix { inherit inputs; })
      // (import ./unit/ghostty.nix { inherit inputs; })
      // (import ./unit/terminal-tools.nix { inherit inputs; })
      // (import ./unit/font-consistency.nix { inherit inputs; })
      // (import ./unit/darwin-omarchy-keybindings.nix { inherit inputs; })
      // (import ./unit/keybindings.nix { inherit inputs; })
      // (import ./unit/native-keybindings.nix { inherit inputs; })
      // (import ./unit/darwin-package-selection.nix { inherit inputs; })
      // (import ./unit/darwin-vendor-bundles.nix { inherit inputs; })
      // (import ./unit/windows-discord.nix { inherit inputs; })
      // (import ./unit/codex-package-selection.nix { inherit inputs; })
      // (import ./unit/devcontainer-packages.nix { inherit inputs; })
      // (import ./unit/orca-packages.nix { inherit inputs; })
      // (import ./unit/browser-packages.nix { inherit inputs; })
      // (import ./unit/comfyui-packages.nix { inherit inputs; })
      // (import ./unit/chatgpt-packages.nix { inherit inputs; })
      // (import ./unit/tart-package-selection.nix { inherit inputs; })
      // (import ./unit/nodejs-package-selection.nix { inherit inputs; })
      // (import ./unit/typescript-language-server.nix { inherit inputs; })
      // (import ./unit/windows-path-metadata.nix { inherit inputs; })
      // (import ./unit/windows-desktop-verifiers.nix { inherit inputs; })
      // (import ./unit/windows-codex-desktop-verifier.nix { inherit inputs; })
      // (import ./unit/windows-wezterm-install-policy.nix { inherit inputs; })
      // (import ./unit/hermes-agent.nix { inherit inputs; })
      // (import ./unit/windows-pnpm.nix { inherit inputs; })
      // (import ./unit/host-package-github-cli.nix { inherit inputs; })
      // (import ./unit/hosts/darwin-layout.nix)
      // (import ./unit/hosts/darwin-configuration.nix { inherit inputs; })
      // (import ./unit/hosts/linux-configuration.nix { inherit inputs; })
      // (import ./unit/hosts/wsl-configuration.nix { inherit inputs; })
      // (import ./unit/flake-outputs.nix { inherit inputs; })
      // (import ./unit/ownership.nix { inherit inputs; });
  };
}
