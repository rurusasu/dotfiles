{ leader }:
let
  # Keybindings as Lua table
  keybindingsLua = ''
    config.keys = {
      -- Pane management
      { key = "h", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
      { key = "v", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
      { key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },

      -- Pane navigation (Vim-like)
      { key = "h", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Left") },
      { key = "j", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Down") },
      { key = "k", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Up") },
      { key = "l", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Right") },

      -- Pane resize
      { key = "LeftArrow", mods = "CTRL|SHIFT", action = act.AdjustPaneSize({ "Left", 5 }) },
      { key = "DownArrow", mods = "CTRL|SHIFT", action = act.AdjustPaneSize({ "Down", 5 }) },
      { key = "UpArrow", mods = "CTRL|SHIFT", action = act.AdjustPaneSize({ "Up", 5 }) },
      { key = "RightArrow", mods = "CTRL|SHIFT", action = act.AdjustPaneSize({ "Right", 5 }) },

      -- Tab management
      { key = "t", mods = "CTRL|SHIFT", action = act.SpawnTab("CurrentPaneDomain") },
      { key = "w", mods = "CTRL|SHIFT", action = act.CloseCurrentTab({ confirm = true }) },
      { key = "Tab", mods = "CTRL", action = act.ActivateTabRelative(1) },
      { key = "Tab", mods = "CTRL|SHIFT", action = act.ActivateTabRelative(-1) },

      -- Copy mode (Vim-like)
      { key = "[", mods = "LEADER", action = act.ActivateCopyMode },

      -- Quick select
      { key = "Space", mods = "LEADER", action = act.QuickSelect },

      -- Font size
      { key = "+", mods = "CTRL", action = act.IncreaseFontSize },
      { key = "-", mods = "CTRL", action = act.DecreaseFontSize },
      { key = "0", mods = "CTRL", action = act.ResetFontSize },
    }

    -- Tab number keybindings (Leader + 1-9)
    for i = 1, 9 do
      table.insert(config.keys, {
        key = tostring(i),
        mods = "LEADER",
        action = act.ActivateTab(i - 1),
      })
    end
  '';

  # Leader key config as Lua table
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
  inherit keybindingsLua leaderLua;
}
