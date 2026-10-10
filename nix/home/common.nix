# Shared Home Manager module for all platforms.
#
# Used by:
#   - nix/hosts/aarch64-darwin/home.nix → nix-darwin Home Manager integration
#   - nix/hosts/shared/linux-home.nix  → native NixOS Home Manager integration
#   - nix/hosts/x86_64-linux/wsl/home.nix    → WSL Home Manager integration
#   - nix/hosts/configurations.nix → standalone homeConfigurations
{
  config,
  lib,
  ...
}:
{
  imports = [
    ../modules/1password
    ../modules/ai_agents/chatgpt
    ../modules/ai_agents/hermes
    ../modules/git
    ../modules/lazygit
    ../modules/starship
    ../modules/ssh.nix
    ../modules/editors/orca
    ../modules/herdr
    ../modules/shells/bash
    ../modules/dsh.nix
    ../modules/shells/plugins/bat.nix
    ../modules/shells/plugins/eza.nix
    ../modules/shells/plugins/fzf.nix
    ../modules/shells/plugins/ripgrep.nix
    ../modules/shells/plugins/zoxide.nix
    ./shells/plugins/bat.nix
    ./shells/plugins/eza.nix
    ./shells/plugins/fd.nix
    ./shells/plugins/fzf.nix
    ./shells/plugins/ripgrep.nix
    ./shells/plugins/zoxide.nix
    ./shells/plugins/zsh-patina.nix
    ./shells/zsh
  ];

  # Integrated configurations use the system GC; standalone uses the native user timer.
  nix.gc = {
    automatic = !config.submoduleSupport.enable;
    dates = "weekly";
    options = "--delete-old";
  };

  home = {
    username = lib.mkDefault "rurusasu";
    stateVersion = lib.mkDefault "26.05";

    sessionVariables = {
      # qmd (markdown search engine)
      QMD_EMBED_MODEL = "hf:Qwen/Qwen3-Embedding-0.6B-GGUF/Qwen3-Embedding-0.6B-Q8_0.gguf";
      QMD_RERANK_MODEL = "hf:giladgd/Qwen3-Reranker-4B-GGUF:Q8_0";
    };

    # PATH: user-local commands and npm global binaries
    sessionPath = [
      "$HOME/.local/bin"
      "$HOME/.local/npm/bin"
    ];
  };

  programs = {
    home-manager.enable = true;

    # ── direnv ─────────────────────────────────────────────────────────────
    direnv = {
      enable = true;
      nix-direnv.enable = true;
      enableZshIntegration = true;
    };
  };
}
