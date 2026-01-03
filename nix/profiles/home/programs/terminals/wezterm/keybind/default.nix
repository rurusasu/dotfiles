{ leader, tabKeys, paneZoomKey }:
let
  # Helper to convert Nix keybinding to Lua string
  mkKey = { key, mods ? null, action }:
    if mods == null then
      ''{ key = "${key}", action = ${action} }''
    else
      ''{ key = "${key}", mods = "${mods}", action = ${action} }'';

  # Keybindings defined in Nix
  keybindings = {
    # Pane split/close/zoom (Ctrl+Alt)
    pane = [
      { key = "h"; mods = "CTRL|ALT"; action = ''act.SplitHorizontal({ domain = "CurrentPaneDomain" })''; }
      { key = "v"; mods = "CTRL|ALT"; action = ''act.SplitVertical({ domain = "CurrentPaneDomain" })''; }
      { key = "x"; mods = "CTRL|ALT"; action = ''act.CloseCurrentPane({ confirm = true })''; }
      { key = paneZoomKey; mods = "CTRL|ALT"; action = "act.TogglePaneZoomState"; }
    ];

    # Pane navigation (Ctrl+Shift + H/J/K/L, Vim-like)
    paneNav = [
      { key = "h"; mods = "CTRL|SHIFT"; action = ''act.ActivatePaneDirection("Left")''; }
      { key = "j"; mods = "CTRL|SHIFT"; action = ''act.ActivatePaneDirection("Down")''; }
      { key = "k"; mods = "CTRL|SHIFT"; action = ''act.ActivatePaneDirection("Up")''; }
      { key = "l"; mods = "CTRL|SHIFT"; action = ''act.ActivatePaneDirection("Right")''; }
    ];

    # Pane resize (Ctrl+Alt + Arrow)
    paneResize = [
      { key = "LeftArrow"; mods = "CTRL|ALT"; action = ''act.AdjustPaneSize({ "Left", 5 })''; }
      { key = "DownArrow"; mods = "CTRL|ALT"; action = ''act.AdjustPaneSize({ "Down", 5 })''; }
      { key = "UpArrow"; mods = "CTRL|ALT"; action = ''act.AdjustPaneSize({ "Up", 5 })''; }
      { key = "RightArrow"; mods = "CTRL|ALT"; action = ''act.AdjustPaneSize({ "Right", 5 })''; }
    ];

    # Tab management (using shared keybindings)
    tab = [
      { key = tabKeys.new; mods = "LEADER"; action = ''act.SpawnTab("CurrentPaneDomain")''; }
      { key = tabKeys.close; mods = "LEADER"; action = ''act.CloseCurrentTab({ confirm = true })''; }
      { key = tabKeys.next; mods = "LEADER"; action = "act.ActivateTabRelative(1)"; }
      { key = tabKeys.prev; mods = "LEADER"; action = "act.ActivateTabRelative(-1)"; }
    ];

    # Misc
    misc = [
      { key = "["; mods = "LEADER"; action = "act.ActivateCopyMode"; }
      { key = "Space"; mods = "LEADER"; action = "act.QuickSelect"; }
      { key = "F11"; action = "act.ToggleFullScreen"; }
    ];

    # Font size
    font = [
      { key = "+"; mods = "CTRL"; action = "act.IncreaseFontSize"; }
      { key = "-"; mods = "CTRL"; action = "act.DecreaseFontSize"; }
      { key = "0"; mods = "CTRL"; action = "act.ResetFontSize"; }
    ];
  };

  # Generate tab number keybindings (Leader + 1-9)
  tabNumbers = builtins.genList (i: {
    key = toString (i + 1);
    mods = "LEADER";
    action = "act.ActivateTab(${toString i})";
  }) 9;

  # Flatten all keybindings
  allKeybindings = with keybindings;
    pane ++ paneNav ++ paneResize ++ tab ++ misc ++ font ++ tabNumbers;

  # Convert to Lua table entries
  keybindingsLuaEntries = builtins.concatStringsSep ",\n      " (map mkKey allKeybindings);

  # Final Lua output
  keybindingsLua = ''
    config.keys = {
      ${keybindingsLuaEntries},
    }
  '';

  # Leader key config as Lua
  leaderLua = ''
    -- Leader key (${leader.mods}+${leader.key})
    config.leader = {
      key = "${leader.key}",
      mods = "${leader.mods}",
      timeout_milliseconds = ${toString leader.timeout},
    }

    -- Alt key sends escape sequence for fzf Alt+C support
    config.send_composed_key_when_left_alt_is_pressed = false
    config.send_composed_key_when_right_alt_is_pressed = false
  '';
in
{
  inherit keybindingsLua leaderLua keybindings;
}
