# Shared Home Manager module for all platforms.
# Uses builtins.getEnv to avoid hardcoding usernames in the repository.
#
# Used by:
#   - nix/home/wsl/users.nix   → NixOS module integration
#   - nix/flakes/home.nix      → standalone homeConfigurations
#   - nix/darwin/default.nix   → nix-darwin Home Manager integration
{
  pkgs,
  lib,
  inputs ? null,
  ...
}:
let
  sets = import ../packages/sets.nix {
    inherit pkgs lib;
  };
  bootstrapUser = builtins.getEnv "DOTFILES_USER";
  bootstrapHome = builtins.getEnv "DOTFILES_HOME";
  user = if bootstrapUser != "" then bootstrapUser else builtins.getEnv "USER";
  home = if bootstrapHome != "" then bootstrapHome else builtins.getEnv "HOME";
  fdOpts = "--hidden --follow --no-ignore-vcs --max-depth 10";
in
{
  home = {
    username = lib.mkDefault (if user != "" then user else "unknown");
    homeDirectory = lib.mkDefault (if home != "" then home else "/home/unknown");
    stateVersion = "25.05";
    packages = sets.all;

    sessionVariables = {
      # qmd (markdown search engine)
      QMD_EMBED_MODEL = "hf:Qwen/Qwen3-Embedding-0.6B-GGUF/Qwen3-Embedding-0.6B-Q8_0.gguf";
      QMD_RERANK_MODEL = "hf:giladgd/Qwen3-Reranker-4B-GGUF:Q8_0";
      # fzf
      FZF_DEFAULT_COMMAND = "fd ${fdOpts} --absolute-path --type f . .";
      FZF_ALT_C_COMMAND = "fd ${fdOpts} --absolute-path --type d . .";
      FZF_DEFAULT_OPTS = "--height=40% --layout=reverse --border --prompt='> '";
      # pnpm global bin directory
      PNPM_HOME = "$HOME/.local/share/pnpm";
    };

    # PATH: bun global binaries (claude-code, gemini-cli, etc.)
    #       pnpm global binaries
    sessionPath = [
      "$HOME/.bun/bin"
      "$HOME/.local/share/pnpm/bin"
      "$HOME/.local/share/pnpm"
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      "/opt/homebrew/bin"
      "/opt/homebrew/sbin"
      "/Applications/Docker.app/Contents/Resources/bin"
    ];
  };

  programs = {
    home-manager.enable = true;

    # ── Shell: zsh ────────────────────────────────────────────────────────
    zsh = {
      enable = true;

      shellAliases = {
        find = "fd";
        grep = "rg";
        l = "eza -lhaT --level=2 --icons=auto --hyperlink -F --group-directories-first --color=auto";
        la = "eza -lhaT --level=2 --icons=auto --hyperlink -F --group-directories-first --color=auto";
        ll = "eza -lhaT --level=2 --icons=auto --hyperlink -F --group-directories-first --color=auto";
        ls = "eza -lhaT --level=1 --icons=auto --hyperlink -F --group-directories-first --color=auto";
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

        # workmux completion
        if command -v workmux >/dev/null 2>&1; then
          eval "$(workmux completions zsh)"
        fi

        # Emit OSC 7 so terminals can open split/tab in current directory
        autoload -Uz add-zsh-hook
        __emit_osc7_cwd() {
          printf '\033]7;file://%s%s\033\\' "$HOST" "$PWD"
        }
        add-zsh-hook precmd __emit_osc7_cwd

        # Disable mouse reporting at the shell prompt.
        # TERM=wezterm exposes mouse-capable terminfo entries; without this,
        # clicks send SGR sequences that zsh prints as literal characters.
        # Programs that need mouse (nvim, tmux) re-enable it themselves.
        __disable_mouse_reporting() {
          printf '\033[?1000l\033[?1002l\033[?1003l\033[?1006l' 2>/dev/null
        }
        add-zsh-hook precmd __disable_mouse_reporting

        # Alt+Q: zoxide interactive (history-based directory jump)
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

        ${builtins.readFile ../../scripts/sh/dcnvim.sh}

        # tm: ghq + fzf でリポジトリ選択 → tmux セッション作成/切替
        tm() {
          if ! command -v tmux &>/dev/null; then
            cd "$(ghq list --full-path | fzf)" 2>/dev/null
            return
          fi
          local repo_slug session_name repo_dir
          repo_slug=$(ghq list | fzf) || return
          session_name=''${repo_slug##*/}
          repo_dir="$(ghq root)/$repo_slug"
          tmux has-session -t "$session_name" 2>/dev/null ||
            tmux new-session -d -c "$repo_dir" -s "$session_name"
          if [[ -n "''${TMUX:-}" ]]; then
            tmux switch-client -t "$session_name"
          else
            tmux attach-session -t "$session_name"
          fi
        }

        # dotf: run task from dotfiles root without changing cwd
        dotf() { (cd ~/.dotfiles && task "$@") }

        codex() {
          local __dotfiles_had_force_secret_load=0
          local __dotfiles_previous_force_secret_load="''${DOTFILES_FORCE_SECRET_LOAD:-}"
          if [ "''${DOTFILES_FORCE_SECRET_LOAD+x}" = x ]; then
            __dotfiles_had_force_secret_load=1
          fi

          if { [ -z "''${GITHUB_PAT_TOKEN:-}" ] || [ -z "''${GITHUB_WORK_TOKEN:-}" ] || [ -z "''${TAVILY_API_KEY:-}" ]; } && [ -f "$HOME/.config/shell/secret.sh" ]; then
            export DOTFILES_FORCE_SECRET_LOAD=1
            source "$HOME/.config/shell/secret.sh"
            if [ "$__dotfiles_had_force_secret_load" = 1 ]; then
              export DOTFILES_FORCE_SECRET_LOAD="$__dotfiles_previous_force_secret_load"
            else
              unset DOTFILES_FORCE_SECRET_LOAD
            fi
          fi

          command codex "$@"
        }

        # 1Password-managed secrets (GITHUB_PAT_TOKEN, TAVILY_API_KEY, etc.)
        [[ -f "$HOME/.config/shell/secret.sh" ]] && source "$HOME/.config/shell/secret.sh"

        # GitHub CLI token switching for personal/work repositories.
        [[ -f "$HOME/.config/shell/gh-token-switch.sh" ]] && source "$HOME/.config/shell/gh-token-switch.sh"
      '';
    };

    # ── Prompt ────────────────────────────────────────────────────────────
    starship.enable = true;

    # ── Directory navigation ───────────────────────────────────────────────
    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };

    # ── direnv ─────────────────────────────────────────────────────────────
    direnv = {
      enable = true;
      nix-direnv.enable = true;
      enableZshIntegration = true;
    };
  };
}
