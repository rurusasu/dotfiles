{ pkgs, lib, ... }:
{
  programs.wezterm = {
    enable = true;
    package = pkgs.wezterm;

    # All settings in Nix
    extraConfig = ''
      local wezterm = require("wezterm")
      local act = wezterm.action

      local config = {}

      if wezterm.config_builder then
        config = wezterm.config_builder()
      end

      -- Color scheme
      config.color_scheme = "Gruvbox Dark"

      -- Font settings
      config.font = wezterm.font("Consolas")
      config.font_size = 12.0

      -- IME support
      config.use_ime = true

      -- Window appearance
      config.window_background_opacity = 0.85
      config.window_decorations = "RESIZE"
      config.window_padding = {
        left = 8,
        right = 8,
        top = 6,
        bottom = 6,
      }

      -- Tab bar settings
      config.enable_tab_bar = true
      config.hide_tab_bar_if_only_one_tab = true
      config.use_fancy_tab_bar = false
      config.tab_bar_at_bottom = false
      config.show_new_tab_button_in_tab_bar = false

      -- Tab colors (Gruvbox)
      config.colors = {
        tab_bar = {
          background = "#1d2021",
          active_tab = {
            bg_color = "#282828",
            fg_color = "#ebdbb2",
            intensity = "Bold",
          },
          inactive_tab = {
            bg_color = "#1d2021",
            fg_color = "#928374",
          },
          inactive_tab_hover = {
            bg_color = "#3c3836",
            fg_color = "#ebdbb2",
          },
        },
      }

      -- Alt key sends escape sequence for fzf Alt+C support
      config.send_composed_key_when_left_alt_is_pressed = false
      config.send_composed_key_when_right_alt_is_pressed = false

      -- Leader key (Ctrl+Q)
      config.leader = { key = "q", mods = "CTRL", timeout_milliseconds = 2000 }

      -- Keybindings
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

      return config
    '';
  };
}
