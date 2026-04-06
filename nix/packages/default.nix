# Package sets for nix profile install
# Usage: nix profile install .#default
#        nix profile install .#minimal
#        nix profile install .#dev
{ pkgs }:
let
  # Core CLI tools - always needed
  core = with pkgs; [
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

    # Archive tools
    unzip
    p7zip
  ];

  # Development tools
  dev = with pkgs; [
    # Languages
    nodejs_22
    python3
    go

    # Rust toolchain
    rustup

    # Build tools
    gnumake
    cmake

    # Repository management
    ghq
  ];

  # AI/LLM tools
  llm = with pkgs; [
    claude-code
    codex
    # cursor-cli  # if available
  ];

  # Communication
  communication = with pkgs; [
    slack
  ];

  # Terminal and shell
  terminal = with pkgs; [
    wezterm
    tmux
    starship
  ];

  # Editors and knowledge tools
  editors = with pkgs; [
    neovim
    obsidian
    # vscode  # Usually installed via OS package manager
  ];

in
{
  # Default: core + dev tools
  default = pkgs.buildEnv {
    name = "dotfiles-default";
    paths = core ++ dev ++ terminal;
  };

  # Minimal: just core tools
  minimal = pkgs.buildEnv {
    name = "dotfiles-minimal";
    paths = core;
  };

  # Full: everything
  full = pkgs.buildEnv {
    name = "dotfiles-full";
    paths = core ++ dev ++ llm ++ communication ++ terminal ++ editors;
  };

  # Individual package sets for selective install
  core = pkgs.buildEnv {
    name = "dotfiles-core";
    paths = core;
  };
  dev = pkgs.buildEnv {
    name = "dotfiles-dev";
    paths = dev;
  };
  llm = pkgs.buildEnv {
    name = "dotfiles-llm";
    paths = llm;
  };
  communication = pkgs.buildEnv {
    name = "dotfiles-communication";
    paths = communication;
  };
  terminal = pkgs.buildEnv {
    name = "dotfiles-terminal";
    paths = terminal;
  };
  editors = pkgs.buildEnv {
    name = "dotfiles-editors";
    paths = editors;
  };
}
