{
  # User shell integration is shared by Darwin, Linux, and WSL homes.
  programs = {
    zoxide = {
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    bash.initExtra = ''
      # Alt+Q: zoxide interactive (history-based directory jump)
      __zoxide_zi_widget() {
        local result
        result="$(zoxide query -i)" || return
        cd "$result" || return

        # Show cwd change immediately even if prompt redraw is delayed.
        printf '\n%s\n' "$PWD"

        READLINE_LINE=""
        READLINE_POINT=0
      }
      bind -x '"\eq": __zoxide_zi_widget'
    '';

    zsh.initContent = ''
      source ${./zoxide.zsh}
    '';
  };
}
