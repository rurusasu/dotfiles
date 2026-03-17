{ lib, pkgs, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.mySettings.wsl.dockerDesktopIntegration = mkOption {
    type = types.bool;
    default = false;
    description = "Enable Docker Desktop WSL2 integration (required for kind to use Docker as container runtime)";
  };

  config = {
    nix = {
      settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        auto-optimise-store = true;
      };
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 7d";
      };
    };

    nixpkgs.config.allowUnfree = true;
    programs.zsh.enable = true;

    programs.git = {
      enable = true;
      config = {
        safe.directory = "*";
      };
    };

    environment.systemPackages = with pkgs; [
      # Dotfiles manager
      chezmoi

      # Version control
      git
      gh

      # Modern CLI replacements
      fd # find alternative
      ripgrep # grep alternative
      bat # cat alternative
      eza # ls alternative
      zoxide # cd alternative
      fzf # fuzzy finder

      # Shell prompt
      starship

      # Editor
      neovim

      # Task runner
      go-task

      # Archive tools
      unzip
      p7zip

      # Python toolchain
      uv

      # JavaScript runtime (for claude-code, gemini-cli, openclaw — pnpm via corepack)
      nodejs_22 # openclaw requires Node.js 22+

      # Secret management
      _1password-cli

      # Formatter & lint runner (for git pre-commit hooks)
      treefmt
      pre-commit
      powershell # provides pwsh for PowerShell test hook

      # AI coding agents
      opencode

      # Kubernetes tools (kind-based local cluster)
      kind # Local Kubernetes clusters using Docker
      kubectl # Kubernetes CLI
      kubernetes-helm # Kubernetes package manager
      k9s # Kubernetes TUI
      kubectx # Fast cluster switching
    ];
  };
}
