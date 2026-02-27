{ lib, pkgs, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.mySettings.wsl.dockerDesktopIntegration = mkOption {
    type = types.bool;
    default = false;
    description = "Enable Docker Desktop WSL2 integration handling for k3s";
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

      # JavaScript runtime (for claude-code, gemini-cli)
      bun

      # AI coding agents
      opencode
    ];
  };
}
