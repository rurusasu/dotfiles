# Shared Home Manager module for all platforms.
# Uses builtins.getEnv to avoid hardcoding usernames in the repository.
#
# Used by:
#   - nix/home/wsl/users.nix   → NixOS module integration
#   - nix/flakes/home.nix      → standalone homeConfigurations
{
  pkgs,
  lib,
  ...
}:
let
  sets = import ../packages/sets.nix { inherit pkgs lib; };
  user = builtins.getEnv "USER";
  home = builtins.getEnv "HOME";
  fdOpts = "--hidden --follow --no-ignore-vcs --max-depth 10";
in
{
  home.username = lib.mkDefault (if user != "" then user else "unknown");
  home.homeDirectory = lib.mkDefault (if home != "" then home else "/home/unknown");
  home.stateVersion = "25.05";
  home.packages = sets.all;
  programs.home-manager.enable = true;

  # ── Shell: zsh ──────────────────────────────────────────────────────────
  programs.zsh = {
    enable = true;

    shellAliases = {
      find = "fd";
      grep = "rg";
    };

    initContent = ''
      # Kubernetes completions and aliases
      if command -v kubectl >/dev/null 2>&1; then
        source <(kubectl completion zsh)
        alias k="kubectl"
        alias kgn="kubectl get nodes"
        alias kgp="kubectl get pods -A"
        alias kgs="kubectl get svc -A"
      fi
      if command -v kind >/dev/null 2>&1; then
        source <(kind completion zsh)
      fi
      if command -v helm >/dev/null 2>&1; then
        source <(helm completion zsh)
      fi
      if command -v kubectx >/dev/null 2>&1; then
        alias kctx="kubectx"
      fi
      if command -v kubens >/dev/null 2>&1; then
        alias kns="kubens"
      fi

      # Task (taskfile.dev) completion
      if command -v task >/dev/null 2>&1; then
        eval "$(task --completion zsh)"
      fi

      # Emit OSC 7 so terminals can open split/tab in current directory
      autoload -Uz add-zsh-hook
      __emit_osc7_cwd() {
        printf '\033]7;file://%s%s\033\\' "$HOST" "$PWD"
      }
      add-zsh-hook precmd __emit_osc7_cwd

      # Alt+q: zoxide interactive (history-based directory jump)
      __zoxide_zi_widget() {
        local result
        result="$(zoxide query -i)" && cd "$result"
        zle reset-prompt
      }
      zle -N __zoxide_zi_widget
      bindkey '^[q' __zoxide_zi_widget

      # Alt+D: fzf directory search and cd
      __fzf_cd_widget() {
        local dir
        dir="$(fd ${fdOpts} --absolute-path -t d . . | fzf)" && cd "$dir"
        zle reset-prompt
      }
      zle -N __fzf_cd_widget
      bindkey '^[d' __fzf_cd_widget

      # Alt+T: fzf file search and insert path
      __fzf_file_widget() {
        local selected
        selected="$(fd ${fdOpts} --absolute-path . . | fzf)"
        if [[ -n "$selected" ]]; then
          LBUFFER="$LBUFFER$selected"
        fi
        zle reset-prompt
      }
      zle -N __fzf_file_widget
      bindkey '^[t' __fzf_file_widget

      # Alt+R: fzf command history search
      __fzf_history_widget() {
        local selected
        selected="$(fc -ln 1 | fzf --tac)"
        if [[ -n "$selected" ]]; then
          BUFFER="$selected"
          CURSOR=$#BUFFER
        fi
        zle reset-prompt
      }
      zle -N __fzf_history_widget
      bindkey '^[r' __fzf_history_widget

      # 1Password-managed secrets (GH_TOKEN, TAVILY_API_KEY, etc.)
      [[ -f "$HOME/.config/shell/secret.sh" ]] && source "$HOME/.config/shell/secret.sh"
    '';
  };

  # ── Prompt ──────────────────────────────────────────────────────────────
  programs.starship.enable = true;

  # ── Directory navigation ─────────────────────────────────────────────────
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  # ── direnv ───────────────────────────────────────────────────────────────
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableZshIntegration = true;
  };

  # ── Environment variables ────────────────────────────────────────────────
  home.sessionVariables = {
    # qmd (markdown search engine)
    QMD_EMBED_MODEL = "hf:Qwen/Qwen3-Embedding-0.6B-GGUF/Qwen3-Embedding-0.6B-Q8_0.gguf";
    QMD_RERANK_MODEL = "hf:giladgd/Qwen3-Reranker-4B-GGUF:Q8_0";
    # fzf
    FZF_DEFAULT_COMMAND = "fd ${fdOpts} --absolute-path --type f . .";
    FZF_ALT_C_COMMAND = "fd ${fdOpts} --absolute-path --type d . .";
    FZF_DEFAULT_OPTS = "--height=40% --layout=reverse --border --prompt='> '";
  };

  # PATH: bun global binaries (claude-code, gemini-cli, etc.)
  home.sessionPath = [ "$HOME/.bun/bin" ];
}
