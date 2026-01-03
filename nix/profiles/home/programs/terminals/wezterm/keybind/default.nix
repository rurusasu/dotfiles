{ leader }:
let
  # Helper to convert Nix keybinding to Lua string
  mkKey = { key, mods, action }:
    ''{ key = "${key}", mods = "${mods}", action = ${action} }'';

  # Keybindings defined in Nix
  keybindings = {
    # Pane split (Leader + h/v/x)
    pane = [
      { key = "h"; mods = "LEADER"; action = ''act.SplitHorizontal({ domain = "CurrentPaneDomain" })''; }
      { key = "v"; mods = "LEADER"; action = ''act.SplitVertical({ domain = "CurrentPaneDomain" })''; }
      { key = "x"; mods = "LEADER"; action = ''act.CloseCurrentPane({ confirm = true })''; }
    ];

    # Pane navigation (Ctrl+Shift + H/J/K/L, Vim-like)
    paneNav = [
      { key = "h"; mods = "CTRL|SHIFT"; action = ''act.ActivatePaneDirection("Left")''; }
      { key = "j"; mods = "CTRL|SHIFT"; action = ''act.ActivatePaneDirection("Down")''; }
      { key = "k"; mods = "CTRL|SHIFT"; action = ''act.ActivatePaneDirection("Up")''; }
      { key = "l"; mods = "CTRL|SHIFT"; action = ''act.ActivatePaneDirection("Right")''; }
    ];

    # Pane resize (Ctrl+Shift + Arrow)
    paneResize = [
      { key = "LeftArrow"; mods = "CTRL|SHIFT"; action = ''act.AdjustPaneSize({ "Left", 5 })''; }
      { key = "DownArrow"; mods = "CTRL|SHIFT"; action = ''act.AdjustPaneSize({ "Down", 5 })''; }
      { key = "UpArrow"; mods = "CTRL|SHIFT"; action = ''act.AdjustPaneSize({ "Up", 5 })''; }
      { key = "RightArrow"; mods = "CTRL|SHIFT"; action = ''act.AdjustPaneSize({ "Right", 5 })''; }
    ];

    # Tab management
    tab = [
      { key = "t"; mods = "CTRL|SHIFT"; action = ''act.SpawnTab("CurrentPaneDomain")''; }
      { key = "w"; mods = "CTRL|SHIFT"; action = ''act.CloseCurrentTab({ confirm = true })''; }
      { key = "Tab"; mods = "CTRL"; action = "act.ActivateTabRelative(1)"; }
      { key = "Tab"; mods = "CTRL|SHIFT"; action = "act.ActivateTabRelative(-1)"; }
    ];

    # Misc
    misc = [
      { key = "["; mods = "LEADER"; action = "act.ActivateCopyMode"; }
      { key = "Space"; mods = "LEADER"; action = "act.QuickSelect"; }
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
