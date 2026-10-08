{ config, ... }:
{
  # Home Manager generates PNPM_HOME and adds its bin directory to PATH.
  programs.pnpm.pnpmHome = "${config.xdg.dataHome}/pnpm";
}
