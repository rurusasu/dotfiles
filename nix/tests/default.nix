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
        docker-mcp = import ./build/modules/ai_agents/docker-mcp.nix { inherit inputs pkgs; };
        aerospace-workspace-cycle = import ./build/modules/aerospace/aerospace-cycle.nix { inherit pkgs; };
        docker-desktop-activation = import ./build/modules/docker/desktop-activation.nix {
          inherit inputs pkgs;
        };
        wezterm-config = import ./build/modules/terminals/wezterm/default.nix { inherit inputs pkgs; };
        custom-package-builds = import ./build/defaults/custom-packages.nix {
          inherit inputs pkgs;
          chatgptDesktopCheck = config.checks.chatgpt-desktop or null;
        };
        neovim-native = import ./build/modules/editors/nvim/default.nix { inherit inputs pkgs; };
        powershell-formatter = import ./build/treefmt/powershell.nix {
          inherit pkgs;
          formatter = config.treefmt.settings.formatter.powershell;
        };
        chatgpt-desktop = import ./build/modules/ai_agents/chatgpt/desktop.nix {
          pkgs = (import ./fixtures/packages.nix { inherit inputs; }).mkPkgs pkgs.stdenv.hostPlatform.system;
        };
        codex-config-migration = import ./build/modules/ai_agents/chatgpt/codex-config-migration.nix {
          inherit inputs pkgs;
        };
        hermes-configuration = import ./build/modules/ai_agents/hermes/configuration.nix {
          inherit inputs pkgs;
        };
        hermes-version = import ./build/modules/ai_agents/hermes/version.nix {
          inherit inputs pkgs;
        };
      }
      // pkgs.lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
        strata-applications = import ./build/modules/ai_agents/strata/default.nix {
          inherit inputs pkgs;
        };
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        standalone-darwin-home = import ./build/defaults/standalone-darwin-home.nix {
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
          docker-mcp
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
          strata-release
          systems
          treefmt-nix
          xurl
          ;
      };

      nix-unit.tests =
        (import ./unit/defaults/import-boundary.nix)
        // (import ./unit/defaults/platform-boundary.nix)
        // (import ./unit/defaults/composition.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/shells/bash/default.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/shells/plugins/bat.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/browsers/chrome/default.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/ai_agents/chatgpt/home.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/ai_agents/docker-mcp.nix { inherit inputs; })
        // (import ./unit/modules/shells/plugins/eza.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/shells/plugins/fd.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/shells/plugins/fzf.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/terminals/ghostty/home.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/git/ghq.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/git/default.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/fonts/gtk.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/git/gwq.nix { inherit inputs homeConfigurations; })
        // (import ./unit/defaults/nautilus-package-selection.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/editors/nvim/default.nix { inherit inputs homeConfigurations; })
        // (import ./unit/defaults/nix-gc.nix { inherit inputs homeConfigurations; })
        // (import ./unit/defaults/obsidian-package-selection.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/1password/default.nix { inherit inputs homeConfigurations; })
        // (import ./unit/defaults/pnpm.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/shells/plugins/ripgrep.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/editors/nvim/runtime.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/ssh.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/shells/plugins/starship/default.nix {
          inherit inputs homeConfigurations;
        })
        // (import ./unit/modules/terminals/wezterm/home.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/shells/plugins/zoxide.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/shells/plugins/zsh-patina.nix { inherit inputs homeConfigurations; })
        // (import ./unit/modules/shells/zsh/default.nix { inherit inputs homeConfigurations; })
        // (import ./unit/defaults/standalone-darwin-identity.nix { inherit inputs; })
        // (import ./unit/modules/shells/zsh/rebuild-aliases.nix { inherit inputs; })
        // (import ./unit/modules/terminals/ghostty/default.nix { inherit inputs; })
        // (import ./unit/defaults/terminal-tools.nix { inherit inputs; })
        // (import ./unit/modules/terminals/appearance.nix)
        // (import ./unit/modules/terminals/wezterm/default.nix { inherit inputs; })
        // (import ./unit/modules/fonts/default.nix { inherit inputs; })
        // (import ./unit/modules/aerospace/default.nix { inherit inputs; })
        // (import ./unit/home/keybindings/bindings.nix { inherit inputs; })
        // (import ./unit/defaults/native-keybindings.nix { inherit inputs; })
        // (import ./unit/modules/hyprland/default.nix { inherit inputs; })
        // (import ./unit/defaults/darwin-package-selection.nix { inherit inputs; })
        // (import ./unit/modules/browsers/dia/default.nix { inherit inputs; })
        // (import ./unit/modules/ai_agents/chatgpt/codex-packages.nix { inherit inputs; })
        // (import ./unit/modules/editors/nvim/devcontainer.nix { inherit inputs; })
        // (import ./unit/defaults/dsh-package-selection.nix { inherit inputs homeConfigurations; })
        // (import ./unit/defaults/orca-package-selection.nix { inherit inputs; })
        // (import ./unit/modules/browsers/dia/packages.nix { inherit inputs; })
        // (import ./unit/defaults/comfyui-package-selection.nix { inherit inputs; })
        // (import ./unit/modules/ai_agents/chatgpt/packages.nix { inherit inputs homeConfigurations; })
        // (import ./unit/defaults/tart-package-selection.nix { inherit inputs homeConfigurations; })
        // (import ./unit/defaults/nodejs-package-selection.nix { inherit inputs; })
        // (import ./unit/modules/ai_agents/hermes/default.nix { inherit inputs; })
        // (import ./unit/modules/ai_agents/strata/default.nix { inherit inputs; })
        // (import ./unit/windows/pnpm.nix { inherit inputs; })
        // (import ./unit/defaults/github-cli-package-selection.nix { inherit inputs; })
        // (import ./unit/defaults/darwin-configuration.nix { inherit inputs; })
        // (import ./unit/defaults/linux-configuration.nix { inherit inputs; })
        // (import ./unit/defaults/wsl-configuration.nix { inherit inputs; })
        // (import ./unit/defaults/outputs.nix { inherit inputs; })
        // (import ./unit/ownership.nix { inherit inputs; });
    };
}
