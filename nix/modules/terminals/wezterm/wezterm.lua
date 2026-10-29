local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()

local is_macos = wezterm.target_triple:find("darwin") ~= nil

-- Window focus: h=left, l=right
local function focus_adjacent_window(direction)
    local offset = direction == "right" and 1 or -1
    return act.ActivateWindowRelative(offset)
end

-- Terminal type (enables undercurl, colored underlines, etc.)
config.term = "wezterm"

config.automatically_reload_config = true

-- Font settings
config.line_height = 1.0
config.cell_width = 1.0

-- IME support
config.use_ime = true

-- Window appearance
config.window_background_opacity = 0.75
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
config.leader = { key = "Space", mods = "CTRL", timeout_milliseconds = 1000 }

-- Force snacks.nvim to recognise WezTerm's Kitty graphics protocol support.
config.set_environment_variables = {
    SNACKS_WEZTERM = "true",
}

-- zsh resolves TERM=wezterm before .zshenv loads Home Manager's terminfo path.
-- The Home Manager module provides the package's terminfo path before this Lua.
if is_macos then
    local inherited_terminfo_dirs = os.getenv("TERMINFO_DIRS")
    local terminfo_dirs = dotfiles_terminfo_directory .. ":/usr/share/terminfo"
    if inherited_terminfo_dirs and inherited_terminfo_dirs ~= "" then
        terminfo_dirs = terminfo_dirs .. ":" .. inherited_terminfo_dirs
    end
    config.set_environment_variables.TERMINFO_DIRS = terminfo_dirs
end

-- Alt key sends escape sequence for fzf Alt+C support
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false

config.keys = {
    -- Shift+Enter → insert newline (Codex and other multi-line prompts)
    { key = "Return", mods = "SHIFT", action = act.SendString("\n") },
    -- Preserve Backspace when it is pressed immediately after the leader key.
    { key = "Backspace", mods = "LEADER", action = act.SendKey({ key = "Backspace" }) },
    -- Pass Ctrl+Shift+h/l through to Neovim; WezTerm defaults Ctrl+Shift+l to the debug overlay.
    { key = "h", mods = "CTRL|SHIFT", action = act.SendKey({ key = "h", mods = "CTRL|SHIFT" }) },
    { key = "l", mods = "CTRL|SHIFT", action = act.SendKey({ key = "l", mods = "CTRL|SHIFT" }) },

    -- Alt+key → send ESC sequence for fzf/zoxide/PSReadLine bindings
    { key = "q", mods = "ALT", action = act.SendString("\x1bq") },
    { key = "d", mods = "ALT", action = act.SendString("\x1bd") },
    { key = "t", mods = "ALT", action = act.SendString("\x1bt") },
    { key = "r", mods = "ALT", action = act.SendString("\x1br") },

    -- Pane zoom remains outside the window-manager contract.
    { key = "w", mods = "CTRL|ALT", action = act.TogglePaneZoomState },

    -- Common terminal window-manager contract.
    { key = "Space", mods = "LEADER|CTRL", action = act.SendKey({ key = "Space", mods = "CTRL" }) },
    { key = "w", mods = "LEADER", action = act.ShowLauncherArgs({ flags = "WORKSPACES" }) },
    {
        key = "a",
        mods = "LEADER",
        action = act.PromptInputLine({
            description = "Enter name for new workspace",
            action = wezterm.action_callback(function(window, pane, line)
                if line and line ~= "" then
                    window:perform_action(act.SwitchToWorkspace({ name = line }), pane)
                end
            end),
        }),
    },
    { key = "q", mods = "LEADER", action = act.CloseCurrentTab({ confirm = true }) },
    { key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },
    { key = "g", mods = "LEADER", action = act.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES|TABS|DOMAINS" }) },
    { key = "d", mods = "LEADER", action = act.DetachDomain("CurrentPaneDomain") },

    -- Match the WSL Ghostty keybindings for splits, tabs, and panes.
    { key = "e", mods = "CTRL|SHIFT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
    { key = "o", mods = "CTRL|SHIFT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
    { key = "t", mods = "CTRL|SHIFT", action = act.SpawnTab("CurrentPaneDomain") },
    { key = "LeftArrow", mods = "CTRL|SHIFT", action = act.ActivateTabRelative(-1) },
    { key = "UpArrow", mods = "CTRL|SHIFT", action = act.ActivateTabRelative(-1) },
    { key = "RightArrow", mods = "CTRL|SHIFT", action = act.ActivateTabRelative(1) },
    { key = "DownArrow", mods = "CTRL|SHIFT", action = act.ActivateTabRelative(1) },
    { key = "LeftArrow", mods = "CTRL|ALT", action = act.ActivatePaneDirection("Left") },
    { key = "DownArrow", mods = "CTRL|ALT", action = act.ActivatePaneDirection("Down") },
    { key = "UpArrow", mods = "CTRL|ALT", action = act.ActivatePaneDirection("Up") },
    { key = "RightArrow", mods = "CTRL|ALT", action = act.ActivatePaneDirection("Right") },
    { key = "LeftArrow", mods = "CTRL|ALT|SHIFT", action = act.AdjustPaneSize({ "Left", 1 }) },
    { key = "DownArrow", mods = "CTRL|ALT|SHIFT", action = act.AdjustPaneSize({ "Down", 1 }) },
    { key = "UpArrow", mods = "CTRL|ALT|SHIFT", action = act.AdjustPaneSize({ "Up", 1 }) },
    { key = "RightArrow", mods = "CTRL|ALT|SHIFT", action = act.AdjustPaneSize({ "Right", 1 }) },
    { key = "Home", mods = "CTRL|ALT|SHIFT", action = act.AdjustPaneSize({ "Left", 10 }) },
    { key = "PageDown", mods = "CTRL|ALT|SHIFT", action = act.AdjustPaneSize({ "Down", 10 }) },
    { key = "PageUp", mods = "CTRL|ALT|SHIFT", action = act.AdjustPaneSize({ "Up", 10 }) },
    { key = "End", mods = "CTRL|ALT|SHIFT", action = act.AdjustPaneSize({ "Right", 10 }) },

    -- Misc
    { key = "[", mods = "LEADER", action = act.ActivateCopyMode },
    { key = "c", mods = "LEADER", action = act.CopyTo("Clipboard") },
    { key = "F11", action = act.ToggleFullScreen },

    -- Disable default font size bindings except Ctrl+Shift+{+/-/0}
    { key = "+", mods = "CTRL", action = act.DisableDefaultAssignment },
    { key = "-", mods = "CTRL", action = act.DisableDefaultAssignment },
    { key = "=", mods = "CTRL", action = act.DisableDefaultAssignment },
    { key = "0", mods = "CTRL", action = act.DisableDefaultAssignment },
    { key = "=", mods = "CTRL|SHIFT", action = act.DisableDefaultAssignment },
    { key = "\\", mods = "CTRL|SHIFT", action = act.DisableDefaultAssignment },

    -- Font size via Ctrl+Shift+{+/-/0}
    { key = "+", mods = "CTRL|SHIFT", action = act.IncreaseFontSize },
    { key = "-", mods = "CTRL|SHIFT", action = act.DecreaseFontSize },
    { key = "0", mods = "CTRL|SHIFT", action = act.ResetFontSize },
}

if is_macos then
    -- Bypass macOS IME processing so Backspace cannot be inserted as a space.
    table.insert(config.keys, 1, {
        key = "Backspace",
        mods = "NONE",
        action = act.SendString("\x7f"),
    })
end

for tab = 1, 9 do
    table.insert(config.keys, {
        key = tostring(tab),
        mods = "ALT",
        action = act.ActivateTab(tab - 1),
    })
end

-- Disable unused built-in tab/window-manager shortcuts. Chords assigned above
-- already override defaults; disabling them here would erase those assignments.
local default_window_manager_bindings = {
    { key = "Tab", mods = "CTRL" },
    { key = "Tab", mods = "SHIFT|CTRL" },
    { key = "!", mods = "CTRL" },
    { key = "!", mods = "SHIFT|CTRL" },
    { key = '"', mods = "ALT|CTRL" },
    { key = '"', mods = "SHIFT|ALT|CTRL" },
    { key = "#", mods = "CTRL" },
    { key = "#", mods = "SHIFT|CTRL" },
    { key = "$", mods = "CTRL" },
    { key = "$", mods = "SHIFT|CTRL" },
    { key = "%", mods = "CTRL" },
    { key = "%", mods = "SHIFT|CTRL" },
    { key = "%", mods = "ALT|CTRL" },
    { key = "%", mods = "SHIFT|ALT|CTRL" },
    { key = "&", mods = "CTRL" },
    { key = "&", mods = "SHIFT|CTRL" },
    { key = "'", mods = "SHIFT|ALT|CTRL" },
    { key = "(", mods = "CTRL" },
    { key = "(", mods = "SHIFT|CTRL" },
    { key = "*", mods = "CTRL" },
    { key = "*", mods = "SHIFT|CTRL" },
    { key = "1", mods = "SHIFT|CTRL" },
    { key = "1", mods = "SUPER" },
    { key = "2", mods = "SHIFT|CTRL" },
    { key = "2", mods = "SUPER" },
    { key = "3", mods = "SHIFT|CTRL" },
    { key = "3", mods = "SUPER" },
    { key = "4", mods = "SHIFT|CTRL" },
    { key = "4", mods = "SUPER" },
    { key = "5", mods = "SHIFT|CTRL" },
    { key = "5", mods = "SHIFT|ALT|CTRL" },
    { key = "5", mods = "SUPER" },
    { key = "6", mods = "SHIFT|CTRL" },
    { key = "6", mods = "SUPER" },
    { key = "7", mods = "SHIFT|CTRL" },
    { key = "7", mods = "SUPER" },
    { key = "8", mods = "SHIFT|CTRL" },
    { key = "8", mods = "SUPER" },
    { key = "9", mods = "SHIFT|CTRL" },
    { key = "9", mods = "SUPER" },
    { key = "@", mods = "CTRL" },
    { key = "@", mods = "SHIFT|CTRL" },
    { key = "W", mods = "CTRL" },
    { key = "Z", mods = "CTRL" },
    { key = "Z", mods = "SHIFT|CTRL" },
    { key = "[", mods = "SHIFT|SUPER" },
    { key = "]", mods = "SHIFT|SUPER" },
    { key = "^", mods = "CTRL" },
    { key = "^", mods = "SHIFT|CTRL" },
    { key = "t", mods = "SUPER" },
    { key = "w", mods = "CTRL|SHIFT" },
    { key = "w", mods = "SUPER" },
    { key = "z", mods = "SHIFT|CTRL" },
    { key = "{", mods = "SUPER" },
    { key = "{", mods = "SHIFT|SUPER" },
    { key = "}", mods = "SUPER" },
    { key = "}", mods = "SHIFT|SUPER" },
    { key = "PageUp", mods = "CTRL" },
    { key = "PageUp", mods = "SHIFT|CTRL" },
    { key = "PageDown", mods = "CTRL" },
    { key = "PageDown", mods = "SHIFT|CTRL" },
}

for _, binding in ipairs(default_window_manager_bindings) do
    table.insert(config.keys, {
        key = binding.key,
        mods = binding.mods,
        action = act.DisableDefaultAssignment,
    })
end

-- GUI window focus stays direct; pane navigation uses Ctrl+Alt+Arrow.
-- Existing direct resize chords remain available on each platform.
local direct_window_bindings
if is_macos then
    direct_window_bindings = {
        { key = "h", mods = "SUPER|ALT", action = focus_adjacent_window("left") },
        { key = "l", mods = "SUPER|ALT", action = focus_adjacent_window("right") },
        -- iTerm2-style pane resize: hold Ctrl+Command and repeat Arrow
        { key = "LeftArrow", mods = "SUPER|CTRL", action = act.AdjustPaneSize({ "Left", 1 }) },
        { key = "UpArrow", mods = "SUPER|CTRL", action = act.AdjustPaneSize({ "Up", 1 }) },
        { key = "RightArrow", mods = "SUPER|CTRL", action = act.AdjustPaneSize({ "Right", 1 }) },
        { key = "DownArrow", mods = "SUPER|CTRL", action = act.AdjustPaneSize({ "Down", 1 }) },
    }
else
    direct_window_bindings = {
        { key = "h", mods = "ALT|SHIFT", action = focus_adjacent_window("left") },
        { key = "l", mods = "ALT|SHIFT", action = focus_adjacent_window("right") },
        { key = "LeftArrow", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Left", 5 }) },
        { key = "UpArrow", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Up", 5 }) },
        { key = "RightArrow", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Right", 5 }) },
        { key = "DownArrow", mods = "ALT|SHIFT", action = act.AdjustPaneSize({ "Down", 5 }) },
    }
end

for _, binding in ipairs(direct_window_bindings) do
    table.insert(config.keys, binding)
end

return config
