{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  omarchy = builtins.fromTOML (builtins.readFile (inputs.omarchy + "/config/herdr/config.toml"));
in
{
  config = lib.mkIf config.programs.herdr.enable {
    home.packages = lib.optional (
      pkgs.stdenv.hostPlatform.isLinux && config.programs.herdr.settings.ui.sound.enabled
    ) pkgs.pulseaudio;
    programs.herdr = {
      package = lib.mkDefault inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
      # Herdr's onboarding and settings UI save to the standard config file.
      mutableSettings = true;
      settings = {
        onboarding = false;
        inherit (omarchy) keys;
        terminal = {
          default_shell = lib.getExe (
            if config.programs.zsh.enable then config.programs.zsh.package else pkgs.bashInteractive
          );
          shell_mode = "auto";
          new_cwd = "follow";
          kitty_graphics = true;
        };
        worktrees.directory =
          if config.programs.gwq.enable then
            config.programs.gwq.settings.worktree.basedir
          else
            config.home.homeDirectory + "/worktrees";
        remote.manage_ssh_config = true;
        theme = {
          name = "terminal";
          auto_switch = false;
        };
        ui = {
          toast = {
            delivery = "herdr";
            delay_seconds = 1;
            herdr.position = "bottom-right";
          };
          sound.enabled = true;
          status_indicators = "symbols";
          tab_bar_right = [
            { type = "zoom"; }
            { type = "hostname"; }
            {
              type = "datetime";
              format = "%H:%M";
            }
          ];
        };
      };
    };
  };
}
