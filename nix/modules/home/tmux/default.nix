# Tmux shared options module
{ config, lib, ... }:
with lib;
{
  options.myHomeSettings.tmux = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable tmux terminal multiplexer";
    };

    # Use shared terminals leader key by default, but allow override
    prefix = {
      key = mkOption {
        type = types.str;
        default = "b";
        description = "Tmux prefix key (default: b for Ctrl+b)";
      };
      useTerminalsLeader = mkOption {
        type = types.bool;
        default = false;
        description = "Use terminals.leader config for tmux prefix";
      };
    };

    keybindings = {
      paneNavStyle = mkOption {
        type = types.enum [ "vim" "arrow" ];
        default = config.myHomeSettings.terminals.keybindings.paneNavStyle;
        description = "Pane navigation style: vim (hjkl) or arrow keys";
      };
    };
  };
}
