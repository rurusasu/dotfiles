{ pkgs, ... }:
{
  home.packages = [ pkgs.wezterm.terminfo ];
  programs.zsh.envExtra = ''
    if [[ "''${TERM-}" == wezterm && -d "/etc/profiles/per-user/''${USER}/share/terminfo" ]]; then
      export TERMINFO_DIRS="/etc/profiles/per-user/''${USER}/share/terminfo''${TERMINFO_DIRS:+:$TERMINFO_DIRS}:/usr/share/terminfo"
    fi
  '';
}
