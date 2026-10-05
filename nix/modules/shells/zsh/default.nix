{
  config,
  pkgs,
  ...
}:
{
  # ── Shell: zsh ────────────────────────────────────────────────────────
  programs.zsh = {
    enable = true;
    package = pkgs.zsh;
    setOptions = [
      "AUTO_CD"
      "NO_BEEP"
      "NUMERIC_GLOB_SORT"
    ];
    # zsh-autocomplete が compinit を実行するため、重複初期化を避ける。
    enableCompletion = false;
    plugins = [
      {
        name = "zsh-autocomplete";
        src = pkgs.zsh-autocomplete;
        file = "share/zsh-autocomplete/zsh-autocomplete.plugin.zsh";
      }
    ];
    history = {
      path = "${config.xdg.stateHome}/zsh/history";
      size = 10000;
      save = 10000;
      append = true;
      share = true;
      extended = true;
      ignoreDups = true;
      ignoreSpace = true;
      saveNoDups = true;
      expireDuplicatesFirst = true;
    };

    shellAliases = {
      find = "fd";
      grep = "rg";
      lg = "lazygit";
      l = "eza -lhaT --level=2 --icons=auto --hyperlink -F --group-directories-first --color=auto";
      la = "eza -lhaT --level=2 --icons=auto --hyperlink -F --group-directories-first --color=auto";
      ll = "eza -lhaT --level=2 --icons=auto --hyperlink -F --group-directories-first --color=auto";
      ls = "eza -lhaT --level=1 --icons=auto --hyperlink -F --group-directories-first --color=auto";
    };

    initContent = ''
      # Backspace / Delete のキー設定。
      bindkey '^?' backward-delete-char
      bindkey '^H' backward-delete-char
      if zmodload -F zsh/terminfo +p:terminfo; then
        if [[ -n "''${terminfo[kdch1]:-}" ]]; then
          bindkey "''${terminfo[kdch1]}" delete-char
        fi
      fi
      bindkey '^[[3~' delete-char

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

      # Disable mouse reporting at the shell prompt.
      # TERM=wezterm exposes mouse-capable terminfo entries; without this,
      # clicks send SGR sequences that zsh prints as literal characters.
      # Programs that need mouse (nvim, tmux) re-enable it themselves.
      __disable_mouse_reporting() {
        printf '\033[?1000l\033[?1002l\033[?1003l\033[?1006l' 2>/dev/null
      }
      add-zsh-hook precmd __disable_mouse_reporting

      ${builtins.readFile ../../../../scripts/sh/dcnvim.sh}

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
}
