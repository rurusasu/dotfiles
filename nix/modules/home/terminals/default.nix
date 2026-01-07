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
        type = types.enum [
          "vim"
          "arrow"
        ];
        default = "vim";
        description = "Pane navigation style: vim (hjkl) or arrow keys";
      };

      # Pane zoom/maximize
      paneZoom = mkOption {
        type = types.str;
        default = "w";
        description = "Key for toggling pane zoom/maximize (after leader/prefix)";
      };

      # Tab/window management (shared across terminals, tmux, nvim)
      tab = {
        new = mkOption {
          type = types.str;
          default = "t";
          description = "Key for new tab (after leader/prefix)";
        };
        close = mkOption {
          type = types.str;
          default = "x";
          description = "Key for closing tab (after leader/prefix)";
        };
        next = mkOption {
          type = types.str;
          default = "l";
          description = "Key for next tab";
        };
        prev = mkOption {
          type = types.str;
          default = "h";
          description = "Key for previous tab";
        };
      };
    };
  };

  # No config section - this module only defines options
  # Actual configuration is done in profiles/home/programs/terminals/
}
