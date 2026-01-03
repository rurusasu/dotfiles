# Tmux configuration
# Options are defined in nix/modules/home/tmux/
{ config, lib, ... }:
with lib;
let
  cfg = config.myHomeSettings.tmux;
  terminalsCfg = config.myHomeSettings.terminals;

  # Convert terminals leader to tmux prefix if enabled
  tmuxPrefix = if cfg.prefix.useTerminalsLeader then
    let
      # Map terminal mods to tmux format
      modsMap = {
        "CTRL" = "C";
        "ALT" = "M";
        "SHIFT" = "S";
      };
      mods = builtins.head (lib.splitString "|" terminalsCfg.leader.mods);
      modKey = modsMap.${mods} or "C";
      key = lib.toLower terminalsCfg.leader.key;
    in "${modKey}-${key}"
  else "C-${cfg.prefix.key}";

  # Pane navigation keybindings based on style
  paneNavBindings = if cfg.keybindings.paneNavStyle == "vim" then ''
    # Vim-style pane navigation
    bind h select-pane -L
    bind j select-pane -D
    bind k select-pane -U
    bind l select-pane -R
  '' else ''
    # Arrow-style pane navigation
    bind Left select-pane -L
    bind Down select-pane -D
    bind Up select-pane -U
    bind Right select-pane -R
  '';
in
{
  config = mkIf cfg.enable {
    programs.tmux = {
      enable = true;
      prefix = tmuxPrefix;
      keyMode = "vi";
      mouse = true;
      escapeTime = 0;
      historyLimit = 10000;
      baseIndex = 1;

      extraConfig = ''
        # Pane split with same directory
        bind v split-window -h -c "#{pane_current_path}"
        bind h split-window -v -c "#{pane_current_path}"
        bind x kill-pane

        ${paneNavBindings}

        # Resize panes
        bind -r H resize-pane -L 5
        bind -r J resize-pane -D 5
        bind -r K resize-pane -U 5
        bind -r L resize-pane -R 5

        # Tab (window) management (using shared keybindings)
        bind ${terminalsCfg.keybindings.tab.new} new-window -c "#{pane_current_path}"
        bind ${terminalsCfg.keybindings.tab.close} kill-window
        bind ${terminalsCfg.keybindings.tab.next} next-window
        bind ${terminalsCfg.keybindings.tab.prev} previous-window
      '';
    };
  };
}
