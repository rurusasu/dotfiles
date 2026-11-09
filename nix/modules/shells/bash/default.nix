{ config, lib, ... }:
let
  ezaListing =
    level:
    "eza -lhaT --level=${toString level} --icons=auto --hyperlink -F --group-directories-first --color=auto";
in
{
  config = lib.mkIf config.programs.bash.enable {
    home.sessionPath = [
      (config.home.homeDirectory + "/.bun/bin")
      (config.home.homeDirectory + "/.local/bin")
      (config.home.homeDirectory + "/bin")
      (config.home.homeDirectory + "/.local/npm/bin")
    ];
    # Bash configuration is generated together with terminal shell integrations.
    programs.bash = {
      historyFile = config.home.homeDirectory + "/.bash_history";
      historySize = 1000;
      historyFileSize = 2000;
      historyControl = [ "ignoreboth" ];
      historyIgnore = [
        "ls"
        "cd"
        "exit"
      ];
      shellOptions = [
        "histappend"
        "extglob"
        "globstar"
        "checkjobs"
        "checkwinsize"
      ];
      shellAliases =
        lib.optionalAttrs config.programs.ripgrep.enable {
          grep = "rg";
        }
        // lib.optionalAttrs config.programs.fd.enable {
          find = "fd";
        }
        // (
          if config.programs.eza.enable then
            {
              ls = ezaListing 1;
              ll = ezaListing 2;
              la = ezaListing 2;
              l = ezaListing 2;
            }
          else
            {
              ll = "ls -alF";
              la = "ls -A";
              l = "ls -CF";
            }
        );

      initExtra = lib.mkBefore (
        lib.optionalString (!config.programs.eza.enable) ''
          # Preserve GNU ls colors when eza is disabled and dircolors is available.
          if [ -x /usr/bin/dircolors ]; then
            test -r ${
              lib.escapeShellArg (config.home.homeDirectory + "/.dircolors")
            } && eval "$(dircolors -b ${
              lib.escapeShellArg (config.home.homeDirectory + "/.dircolors")
            })" || eval "$(dircolors -b)"
            alias ls='ls --color=auto'
          fi
        ''
        + ''
          export USER_ID="$(id -u)"
          export GROUP_ID="$(id -g)"

          # NVM's user-managed installation and its completion remain optional.
          export NVM_DIR=${lib.escapeShellArg (config.home.homeDirectory + "/.nvm")}
          [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
          [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

          # Run task from the dotfiles root without changing the caller's cwd.
          dotf() { (cd ${lib.escapeShellArg (config.home.homeDirectory + "/.dotfiles")} && task "$@"); }

          codex() {
            local __dotfiles_had_force_secret_load=0
            local __dotfiles_previous_force_secret_load="''${DOTFILES_FORCE_SECRET_LOAD:-}"
            if [ "''${DOTFILES_FORCE_SECRET_LOAD+x}" = x ]; then
              __dotfiles_had_force_secret_load=1
            fi

            if { [ -z "''${GITHUB_PAT_TOKEN:-}" ] || [ -z "''${GITHUB_WORK_TOKEN:-}" ] || [ -z "''${TAVILY_API_KEY:-}" ]; } && [ -f ${
              lib.escapeShellArg (config.xdg.configHome + "/shell/secret.sh")
            } ]; then
              export DOTFILES_FORCE_SECRET_LOAD=1
              source ${lib.escapeShellArg (config.xdg.configHome + "/shell/secret.sh")}
              if [ "$__dotfiles_had_force_secret_load" = 1 ]; then
                export DOTFILES_FORCE_SECRET_LOAD="$__dotfiles_previous_force_secret_load"
              else
                unset DOTFILES_FORCE_SECRET_LOAD
              fi
            fi

            command codex "$@"
          }

          # Keep compatibility with existing user-managed secret/token loaders.
          [[ -f ${lib.escapeShellArg (config.xdg.configHome + "/shell/secret.sh")} ]] && source ${
            lib.escapeShellArg (config.xdg.configHome + "/shell/secret.sh")
          }
          [[ -f ${lib.escapeShellArg (config.xdg.configHome + "/shell/gh-token-switch.sh")} ]] && source ${
            lib.escapeShellArg (config.xdg.configHome + "/shell/gh-token-switch.sh")
          }
        ''
      );
    };
  };
}
