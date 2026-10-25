{
  config,
  lib,
  pkgs,
  ...
}:
{
  # ── Shell: zsh ────────────────────────────────────────────────────────
  programs.zsh = {
    package = pkgs.zsh;
    dotDir = "${config.xdg.configHome}/zsh";
    setOptions = [
      "AUTO_CD"
      "NO_BEEP"
      "NUMERIC_GLOB_SORT"
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
      grep = "rg";
      k = "kubectl";
      kgn = "kubectl get nodes";
      kgp = "kubectl get pods -A";
      kgs = "kubectl get svc -A";
      kctx = "kubectx";
      kns = "kubens";
      nrs = lib.mkDefault "~/.dotfiles/install.sh";
    };
    initContent = lib.mkMerge [
      ''
        # Backspace / Delete のキー設定。
        bindkey '^?' backward-delete-char
        bindkey '^H' backward-delete-char
        if zmodload -F zsh/terminfo +p:terminfo; then
          if [[ -n "''${terminfo[kdch1]:-}" ]]; then
            bindkey "''${terminfo[kdch1]}" delete-char
          fi
        fi
        bindkey '^[[3~' delete-char
      ''
      # Home Manager emits shellAliases at order 1100, between bindings and hooks.
      (lib.mkOrder 1101 ''
        autoload -Uz add-zsh-hook

        # Disable mouse reporting at the shell prompt. Mouse-aware programs re-enable it.
        __disable_mouse_reporting() {
          printf '\033[?1000l\033[?1002l\033[?1003l\033[?1006l' 2>/dev/null
        }
        add-zsh-hook precmd __disable_mouse_reporting
      '')
    ];
    # 補完パッケージは維持し、compinit は zsh-autocomplete に任せる。
    enableCompletion = true;
    completionInit = "";
    plugins = [
      {
        name = "zsh-autocomplete";
        src = pkgs.zsh-autocomplete;
        file = "share/zsh-autocomplete/zsh-autocomplete.plugin.zsh";
      }
    ];
  };

  # zsh-autocomplete writes recent cd locations under XDG_DATA_HOME/zsh.
  # The plugin does not create that parent directory itself.
  home.activation.createZshDataDirectory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p -- ${lib.escapeShellArg "${config.xdg.dataHome}/zsh"}
  '';
}
