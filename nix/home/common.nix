# Shared Home Manager module for all platforms.
#
# Used by:
#   - nix/home/darwin.nix → nix-darwin Home Manager integration
#   - nix/hosts/default.nix linuxHome → native / standalone Linux Home Manager
#   - nix/home/wsl.nix → WSL Home Manager integration
#   - nix/hosts/configurations.nix → standalone homeConfigurations
{
  lib,
  ...
}:
{
  imports = [
    (import ../modules/tools.nix).homeManager
    ./1password.nix
    ../modules/ai_agents/mcp.nix
    (import ../modules/ai_agents/chatgpt).homeManager
    ../modules/ai_agents/hermes
    ../modules/editors/nvim
    ../modules/fonts
    ../modules/git
    ../modules/lazygit
    ../modules/ssh.nix
    ../modules/herdr
    ../modules/shells/bash
    ../modules/shells/plugins/starship
    ../modules/shells/plugins/bat.nix
    ../modules/shells/plugins/eza.nix
    ../modules/shells/plugins/fd.nix
    ../modules/shells/plugins/fzf.nix
    ../modules/shells/plugins/ripgrep.nix
    ../modules/shells/plugins/zoxide.nix
    ../modules/shells/plugins/zsh-patina.nix
    ../modules/shells/zsh
    ../modules/terminals/ghostty
    ../modules/terminals/wezterm
  ];

  home = {
    username = lib.mkDefault "rurusasu";
    stateVersion = lib.mkDefault "26.05";
    preferXdgDirectories = true;

    # Shared user commands, preserving the previous Bash login precedence.
    sessionPath = [
      "$HOME/.bun/bin"
      "$HOME/.local/bin"
      "$HOME/bin"
      "$HOME/.local/npm/bin"
    ];
  };

  xdg.enable = true;

  programs = {
    # ── direnv ─────────────────────────────────────────────────────────────
    direnv = {
      nix-direnv.enable = true;
      enableZshIntegration = true;
    };
  };
}
