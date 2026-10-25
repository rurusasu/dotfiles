{ inputs, ... }:
let
  homeConfigurations = import ./fixtures/home-configurations.nix { inherit inputs; };
in
{
  perSystem =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    {
      imports = [
        {
          options.nix-unit.inputs = lib.mkOption {
            # Preserve regular-file inputs and source revisions in the sandbox.
            apply = lib.mapAttrs (
              _: input: "path:${input}${lib.optionalString (input ? rev) "?rev=${input.rev}"}"
            );
          };
        }
      ];
      checks = {
        aerospace-workspace-cycle = import ./build/aerospace-cycle.nix { inherit pkgs; };
        docker-desktop-activation = import ./build/docker-desktop-activation.nix { inherit inputs pkgs; };
        wezterm-config = import ./build/wezterm-config.nix { inherit inputs pkgs; };
        custom-package-builds = import ./build/custom-packages.nix {
          inherit inputs pkgs;
          chatgptDesktopCheck = config.checks.chatgpt-desktop or null;
        };
        neovim-native = import ./build/neovim.nix { inherit inputs pkgs; };
        powershell-formatter = import ./build/powershell-formatter.nix {
          inherit pkgs;
          formatter = config.treefmt.settings.formatter.powershell;
        };
        chatgpt-desktop = import ./build/chatgpt-desktop.nix {
          pkgs = (import ./fixtures/packages.nix { inherit inputs; }).mkPkgs pkgs.stdenv.hostPlatform.system;
        };
        codex-config-migration = import ./build/codex-config-migration.nix { inherit inputs pkgs; };
        hermes-configuration = import ./build/hermes-configuration.nix { inherit inputs pkgs; };
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
        "mcp-servers/nixpkgs" = inputs.mcp-servers.inputs.nixpkgs;
        inherit (inputs)
          devcontainer-cli-nvim
          dia
          flake-parts
          home-manager
          hermes-agent
          hermes-lcm
          llm-agents
          mcp-servers
          modes-nvim
          nix-darwin
          nix-homebrew
          nix-unit
          nixos-vscode-server
          nixos-wsl
          nixpkgs
          psscriptanalyzer
          systems
          treefmt-nix
          xurl
          ;
      };

      nix-unit.tests =
        (import ./unit/home/import-boundary.nix)
        // (import ./unit/home/platform-boundary.nix)
        // (import ./unit/home/composition.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/bash.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/bat.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/chrome.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/codex.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/eza.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/fd.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/fzf.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/ghostty.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/ghq.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/git.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/gtk.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/gwq.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/nautilus.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/neovim.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/nix-gc.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/obsidian.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/onepassword.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/pnpm.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/ripgrep.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/rust.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/ssh.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/starship.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/wezterm.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/zoxide.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/zsh-patina.nix { inherit inputs homeConfigurations; })
        // (import ./unit/home/zsh.nix { inherit inputs homeConfigurations; })
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
