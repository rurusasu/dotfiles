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

config.automatically_reload_config = true

-- Color scheme: Catppuccin Mocha (shared with Windows Terminal and Neovim).
-- The scheme defines its own cursor/selection colors so no override is needed.
config.color_scheme = "Catppuccin Mocha"

-- Font settings
config.font = wezterm.font("Moralerspace Neon HWJPDOC")
config.font_size = 11.0
config.line_height = 1.15
config.cell_width = 1.0

-- WebGpu renders text more sharply than the legacy OpenGL front end on Windows.
config.front_end = "WebGpu"

-- IME support
config.use_ime = true

-- Window appearance
config.window_background_opacity = 0.85
config.window_decorations = "TITLE|RESIZE"
config.window_padding = {
    left = 8,
    right = 8,
    top = 6,
    bottom = 6,
}

-- Tab bar settings
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = true
config.tab_bar_at_bottom = false
config.show_new_tab_button_in_tab_bar = true

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
    -- Shift+Enter → insert newline (Claude Code, Codex, multi-line prompts)
    { key = "Return", mods = "SHIFT", action = act.SendString("\n") },

    -- Alt+key → send ESC sequence for fzf/zoxide/PSReadLine bindings
    { key = "q", mods = "ALT", action = act.SendString("\x1bq") },
    { key = "d", mods = "ALT", action = act.SendString("\x1bd") },
    { key = "t", mods = "ALT", action = act.SendString("\x1bt") },
    { key = "r", mods = "ALT", action = act.SendString("\x1br") },

    -- Pane split/close/zoom (Ctrl+Alt)
    { key = "\\", mods = "CTRL|ALT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
    { key = "-", mods = "CTRL|ALT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
    { key = "x", mods = "CTRL|ALT", action = act.CloseCurrentPane({ confirm = true }) },
    { key = "w", mods = "CTRL|ALT", action = act.TogglePaneZoomState },

    -- Pane navigation (Ctrl+Alt + H/J/K/L)
    { key = "h", mods = "CTRL|ALT", action = act.ActivatePaneDirection("Left") },
    { key = "j", mods = "CTRL|ALT", action = act.ActivatePaneDirection("Down") },
    { key = "k", mods = "CTRL|ALT", action = act.ActivatePaneDirection("Up") },
    { key = "l", mods = "CTRL|ALT", action = act.ActivatePaneDirection("Right") },

    -- Pane resize (Ctrl+Alt + Arrow)
    { key = "LeftArrow", mods = "CTRL|ALT", action = act.AdjustPaneSize({ "Left", 5 }) },
    { key = "DownArrow", mods = "CTRL|ALT", action = act.AdjustPaneSize({ "Down", 5 }) },
    { key = "UpArrow", mods = "CTRL|ALT", action = act.AdjustPaneSize({ "Up", 5 }) },
    { key = "RightArrow", mods = "CTRL|ALT", action = act.AdjustPaneSize({ "Right", 5 }) },

    -- Tab management (Ctrl+Alt+T or Leader+t=new, Leader+x=close, Ctrl+Tab=nav)
    { key = "t", mods = "CTRL|ALT", action = act.SpawnTab("CurrentPaneDomain") },
    { key = "t", mods = "LEADER", action = act.SpawnTab("CurrentPaneDomain") },
    { key = "x", mods = "LEADER", action = act.CloseCurrentTab({ confirm = true }) },
    { key = "Tab", mods = "CTRL", action = act.ActivateTabRelative(1) },
    { key = "Tab", mods = "CTRL|SHIFT", action = act.ActivateTabRelative(-1) },

    -- Misc
    { key = "[", mods = "LEADER", action = act.ActivateCopyMode },
    { key = "c", mods = "LEADER", action = act.CopyTo("Clipboard") },
    { key = "v", mods = "LEADER", action = act.PasteFrom("Clipboard") },
    { key = "Space", mods = "LEADER", action = act.QuickSelect },
    { key = "F11", action = act.ToggleFullScreen },

    -- Disable all default font size bindings
    { key = "+", mods = "CTRL", action = act.DisableDefaultAssignment },
    { key = "-", mods = "CTRL", action = act.DisableDefaultAssignment },
    { key = "=", mods = "CTRL", action = act.DisableDefaultAssignment },
    { key = "0", mods = "CTRL", action = act.DisableDefaultAssignment },
    { key = "+", mods = "CTRL|SHIFT", action = act.DisableDefaultAssignment },
    { key = "-", mods = "CTRL|SHIFT", action = act.DisableDefaultAssignment },
    { key = "=", mods = "CTRL|SHIFT", action = act.DisableDefaultAssignment },
    { key = "0", mods = "CTRL|SHIFT", action = act.DisableDefaultAssignment },

    -- Font size via LEADER (Ctrl+Space then +/-/0)
    { key = "+", mods = "LEADER", action = act.IncreaseFontSize },
    { key = "-", mods = "LEADER", action = act.DecreaseFontSize },
    { key = "0", mods = "LEADER", action = act.ResetFontSize },

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
