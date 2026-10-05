# Shared Home Manager module for all platforms.
#
# Used by:
#   - nix/home/darwin.nix → nix-darwin Home Manager integration
#   - nix/home/linux.nix  → native NixOS Home Manager integration
#   - nix/home/wsl.nix    → WSL Home Manager integration
#   - nix/flakes/home.nix → standalone homeConfigurations
{
  lib,
  ...
}:
{
  imports = [
    ../modules/fzf.nix
    ../modules/zoxide.nix
    ./fzf.nix
    ./zoxide.nix
  ];

  home = {
    username = lib.mkDefault "rurusasu";
    stateVersion = lib.mkDefault "26.05";

    sessionVariables = {
      # qmd (markdown search engine)
      QMD_EMBED_MODEL = "hf:Qwen/Qwen3-Embedding-0.6B-GGUF/Qwen3-Embedding-0.6B-Q8_0.gguf";
      QMD_RERANK_MODEL = "hf:giladgd/Qwen3-Reranker-4B-GGUF:Q8_0";
      # pnpm global bin directory
      PNPM_HOME = "$HOME/.local/share/pnpm";
    };

    # PATH: user-local Codex npm, bun and pnpm global binaries
    sessionPath = [
      "$HOME/.local/bin"
      "$HOME/.local/npm/bin"
      "$HOME/.bun/bin"
      "$HOME/.local/share/pnpm/bin"
      "$HOME/.local/share/pnpm"
    ];
  };

  programs = {
    home-manager.enable = true;

    # Bash configuration is generated together with terminal shell integrations.
    bash = {
      enable = true;
      initExtra = lib.mkBefore (builtins.readFile ../../chezmoi/shells/bashrc);
      profileExtra = ''
        # Set PATH so it includes user's private bin if it exists
        if [ -d "$HOME/bin" ]; then
          PATH="$HOME/bin:$PATH"
        fi
        if [ -d "$HOME/.local/bin" ]; then
          PATH="$HOME/.local/bin:$PATH"
        fi

        # User-local npm globals (Codex in devcontainers)
        if [ -d "$HOME/.local/npm/bin" ]; then
          case ":$PATH:" in
            *":$HOME/.local/npm/bin:"*) ;;
            *) PATH="$HOME/.local/npm/bin:$PATH" ;;
          esac
        fi

        # bun global binaries
        if [ -d "$HOME/.bun/bin" ]; then
          PATH="$HOME/.bun/bin:$PATH"
        fi

        export PATH
      '';
    };

    # ── Prompt ────────────────────────────────────────────────────────────
    starship.enable = true;
    # The preserved Bash configuration initializes Starship once.
    starship.enableBashIntegration = false;

    # ── direnv ─────────────────────────────────────────────────────────────
    direnv = {
      enable = true;
      nix-direnv.enable = true;
      enableZshIntegration = true;
    };
  };
}
