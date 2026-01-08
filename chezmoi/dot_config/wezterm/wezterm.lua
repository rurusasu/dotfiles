local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()

-- Detect Windows for default shell
local is_windows = wezterm.target_triple:find("windows") ~= nil
if is_windows then
  config.default_prog = { "pwsh.exe", "-NoLogo" }
  config.exit_behavior = "Close"
end

-- Terminal type (enables undercurl, colored underlines, etc.)
config.term = "wezterm"

-- Color scheme
config.color_schemes = {
  ["gruvbox-custom"] = {
    ansi = {
      "#1d2021",
      "#fb4934",
      "#b8bb26",
      "#fabd2f",
      "#83a598",
      "#d3869b",
      "#8ec07c",
      "#d5c4a1",
    },
    brights = {
      "#665c54",
      "#fb4934",
      "#b8bb26",
      "#fabd2f",
      "#83a598",
      "#d3869b",
      "#8ec07c",
      "#fbf1c7",
    },
    background = "#1d2021",
    foreground = "#ebdbb2",
    cursor_bg = "#ebdbb2",
    cursor_fg = "#1d2021",
    selection_bg = "#504945",
    selection_fg = "#ebdbb2",
    split = "#665c54",
    compose_cursor = "#fe8019",
    scrollbar_thumb = "#3c3836",
    tab_bar = {
      background = "#1d2021",
      inactive_tab_edge = "#3c3836",
      active_tab = {
        bg_color = "#3c3836",
        fg_color = "#ebdbb2",
      },
      inactive_tab = {
        bg_color = "#1d2021",
        fg_color = "#665c54",
      },
      inactive_tab_hover = {
        bg_color = "#3c3836",
        fg_color = "#ebdbb2",
      },
      new_tab = {
        bg_color = "#1d2021",
        fg_color = "#665c54",
      },
      new_tab_hover = {
        bg_color = "#3c3836",
        fg_color = "#ebdbb2",
      },
    },
  },
}

config.color_scheme = "gruvbox-custom"

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

-- Leader key (CTRL+Space)
config.leader = {
  key = "Space",
  mods = "CTRL",
  timeout_milliseconds = 2000,
}

-- Alt key sends escape sequence for fzf Alt+C support
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false

config.keys = {
  -- Pane split/close/zoom (Ctrl+Alt)
  { key = "h", mods = "CTRL|ALT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
  { key = "v", mods = "CTRL|ALT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
  { key = "x", mods = "CTRL|ALT", action = act.CloseCurrentPane({ confirm = true }) },
  { key = "w", mods = "CTRL|ALT", action = act.TogglePaneZoomState },

  -- Pane navigation (Ctrl+Shift + H/J/K/L)
  { key = "h", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Left") },
  { key = "j", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Down") },
  { key = "k", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Up") },
  { key = "l", mods = "CTRL|SHIFT", action = act.ActivatePaneDirection("Right") },

  -- Pane resize (Ctrl+Alt + Arrow)
  { key = "LeftArrow", mods = "CTRL|ALT", action = act.AdjustPaneSize({ "Left", 5 }) },
  { key = "DownArrow", mods = "CTRL|ALT", action = act.AdjustPaneSize({ "Down", 5 }) },
  { key = "UpArrow", mods = "CTRL|ALT", action = act.AdjustPaneSize({ "Up", 5 }) },
  { key = "RightArrow", mods = "CTRL|ALT", action = act.AdjustPaneSize({ "Right", 5 }) },

  -- Tab management (Leader)
  { key = "t", mods = "LEADER", action = act.SpawnTab("CurrentPaneDomain") },
  { key = "x", mods = "LEADER", action = act.CloseCurrentTab({ confirm = true }) },
  { key = "l", mods = "LEADER", action = act.ActivateTabRelative(1) },
  { key = "h", mods = "LEADER", action = act.ActivateTabRelative(-1) },

  -- Misc
  { key = "[", mods = "LEADER", action = act.ActivateCopyMode },
  { key = "Space", mods = "LEADER", action = act.QuickSelect },
  { key = "F11", action = act.ToggleFullScreen },

  -- Font size
  { key = "+", mods = "CTRL", action = act.IncreaseFontSize },
  { key = "-", mods = "CTRL", action = act.DecreaseFontSize },
  { key = "0", mods = "CTRL", action = act.ResetFontSize },

  -- Tab numbers
  { key = "1", mods = "LEADER", action = act.ActivateTab(0) },
  { key = "2", mods = "LEADER", action = act.ActivateTab(1) },
  { key = "3", mods = "LEADER", action = act.ActivateTab(2) },
  { key = "4", mods = "LEADER", action = act.ActivateTab(3) },
  { key = "5", mods = "LEADER", action = act.ActivateTab(4) },
  { key = "6", mods = "LEADER", action = act.ActivateTab(5) },
  { key = "7", mods = "LEADER", action = act.ActivateTab(6) },
  { key = "8", mods = "LEADER", action = act.ActivateTab(7) },
  { key = "9", mods = "LEADER", action = act.ActivateTab(8) },
}

return config
