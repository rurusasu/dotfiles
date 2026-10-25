{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.bat.config = {
    theme = "Catppuccin Mocha";
    style = "numbers,changes,header,grid";
    paging = "auto";
  };

  # Normalize man overstrikes before highlighting; keep bat's pager enabled.
  home.sessionVariables = {
    MANPAGER = "${lib.getExe' pkgs.bash "sh"} -c ${lib.escapeShellArg "${lib.getExe pkgs.unixtools.col} -bx | ${lib.getExe config.programs.bat.package} -l man -p"}";
    MANROFFOPT = "-c";
  };
}
