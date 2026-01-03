{ config, pkgs, ... }:
{
  programs.bash = {
    enable = true;
    enableCompletion = true;
    package = pkgs.bash;

    historyControl = [ "ignoreboth" ];
    historyFile = "${config.home.homeDirectory}/.bash_history";
    historySize = 1000;
    historyFileSize = 2000;
    historyIgnore = [
      "ls"
      "cd"
      "exit"
    ];

    shellOptions = [
      "histappend"
      "checkwinsize"
    ];

    shellAliases = {
      ll = "ls -alF";
      la = "ls -A";
      l = "ls -CF";
      grep = "rg";
      find = "fd";
    };

    sessionVariables = {
      USER_ID = "$(id -u)";
      GROUP_ID = "$(id -g)";
      SSH_AUTH_SOCK = "$HOME/.ssh/agent.sock";
    };

    profileExtra = ''
      # set PATH so it includes user's private bin if it exists
      if [ -d "$HOME/bin" ]; then
        PATH="$HOME/bin:$PATH"
      fi
      if [ -d "$HOME/.local/bin" ]; then
        PATH="$HOME/.local/bin:$PATH"
      fi
    '';

    initExtra = ''
      # Color support for ls
      if [ -x /usr/bin/dircolors ]; then
        test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
        alias ls='ls --color=auto'
      fi

      # Fancy prompt
      case "$TERM" in
        xterm-color|*-256color) color_prompt=yes;;
      esac

      if [ "$color_prompt" = yes ]; then
        PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
      else
        PS1='\u@\h:\w\$ '
      fi
      unset color_prompt

      # Set xterm title
      case "$TERM" in
        xterm*|rxvt*)
          PS1="\[\e]0;\u@\h: \w\a\]$PS1"
          ;;
      esac

      # NVM setup
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
      [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

      # SSH agent
      if ! nc -z localhost 22 2>/dev/null; then
        eval "$(ssh-agent -s)" > /dev/null
      fi

      # Alt+Z: zoxide interactive (履歴ベースのディレクトリジャンプ)
      __zoxide_zi_widget() {
        local result
        result="$(${pkgs.zoxide}/bin/zoxide query -i)" && cd "$result"
      }
      bind -x '"\ez": __zoxide_zi_widget'
    '';

    logoutExtra = ''
      # Clear screen on logout for privacy
      if [ "$SHLVL" = 1 ]; then
        [ -x /usr/bin/clear_console ] && /usr/bin/clear_console -q
      fi
    '';
  };
}
