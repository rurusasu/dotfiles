# Terminal emulator shared options module
# Provides common configuration for all terminal emulators
{ config, lib, ... }:
with lib;
{
  options.myHomeSettings.terminals = {
    leader = {
      key = mkOption {
        type = types.str;
        default = "Space";
        description = "Leader key for terminal keybindings (used by WezTerm)";
      };
      mods = mkOption {
        type = types.str;
        default = "CTRL";
        description = "Leader key modifiers (e.g., CTRL, CTRL|SHIFT, WIN)";
      };
      timeout = mkOption {
        type = types.int;
        default = 2000;
        description = "Leader key timeout in milliseconds";
      };
    };

    keybindings = {
      paneNavStyle = mkOption {
        type = types.enum [ "vim" "arrow" ];
        default = "vim";
        description = "Pane navigation style: vim (hjkl) or arrow keys";
      };
    };
  };

  # No config section - this module only defines options
  # Actual configuration is done in profiles/home/programs/terminals/
}
