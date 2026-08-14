local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()

-- Window focus: h=left, l=right
-- Same-process: WezTerm native. Cross-process: Win32 SetForegroundWindow via PowerShell.
local function focus_adjacent_window(direction)
    return wezterm.action_callback(function(window, pane)
        local wins = wezterm.gui.gui_windows()
        table.sort(wins, function(a, b)
            return a:window_id() < b:window_id()
        end)
        if #wins > 1 then
            for i, w in ipairs(wins) do
                if w:window_id() == window:window_id() then
                    local ni = direction == "left" and ((i - 2) % #wins) + 1 or (i % #wins) + 1
                    window:perform_action(act.ActivateWindow(ni - 1), pane)
                    return
                end
            end
        end
        local offset = direction == "right" and "1" or "-1"
        local ps = table.concat({
            "Add-Type -TypeDef 'using System;using System.Runtime.InteropServices;",
            "public class U{",
            '[DllImport("user32")]public static extern IntPtr GetForegroundWindow();',
            '[DllImport("user32")]public static extern bool SetForegroundWindow(IntPtr h);',
            '[DllImport("user32")]public static extern bool ShowWindow(IntPtr h,int n);',
            '[DllImport("user32")]public static extern bool IsIconic(IntPtr h);}\';',
            "$d=" .. offset .. ";",
            "$p=@(Get-Process wezterm-gui -EA 0|Where-Object{$_.MainWindowHandle -ne 0}|Sort-Object Id);",
            "if($p.Count -lt 2){exit};",
            "$h=@($p|ForEach-Object{[IntPtr]$_.MainWindowHandle});",
            "$c=[U]::GetForegroundWindow();",
            "$i=[Array]::IndexOf($h,$c);",
            "if($i -lt 0){exit};",
            "$n=(($i+$d)%$p.Count+$p.Count)%$p.Count;",
            "if([U]::IsIconic($h[$n])){[U]::ShowWindow($h[$n],9)};",
            "[void][U]::SetForegroundWindow($h[$n])",
        })
        wezterm.run_child_process({ "pwsh.exe", "-NoProfile", "-NonInteractive", "-Command", ps })
    end)
end

-- Detect Windows for default shell
local is_windows = wezterm.target_triple:find("windows") ~= nil
local is_macos = wezterm.target_triple:find("darwin") ~= nil
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
config.font = wezterm.font("UDEV Gothic NF")
config.font_size = 10.0
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
-- Auto-detection can fail on Windows where TERM_PROGRAM may not propagate.
config.set_environment_variables = {
    SNACKS_WEZTERM = "true",
}

-- zsh resolves TERM=wezterm while it starts, before .zshenv can restore
-- Home Manager's terminfo path. Provide the Darwin path to child shells
-- directly from WezTerm so startup never begins without a definition.
if is_macos then
    local terminfo_user = os.getenv("USER")
    if terminfo_user and terminfo_user ~= "" then
        local inherited_terminfo_dirs = os.getenv("TERMINFO_DIRS")
        local terminfo_dirs = "/etc/profiles/per-user/" .. terminfo_user .. "/share/terminfo:/usr/share/terminfo"
        if inherited_terminfo_dirs and inherited_terminfo_dirs ~= "" then
            terminfo_dirs = terminfo_dirs .. ":" .. inherited_terminfo_dirs
        end
        config.set_environment_variables.TERMINFO_DIRS = terminfo_dirs
    end
end

-- Alt key sends escape sequence for fzf Alt+C support
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false

config.keys = {
    -- Shift+Enter → insert newline (Claude Code, Codex, multi-line prompts)
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
    { key = "Space", mods = "LEADER", action = act.SendKey({ key = "Space", mods = "CTRL" }) },
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
    { key = "n", mods = "LEADER", action = act.SpawnTab("CurrentPaneDomain") },
    { key = "q", mods = "LEADER", action = act.CloseCurrentTab({ confirm = true }) },
    { key = "Tab", mods = "LEADER", action = act.ActivateTabRelative(1) },
    { key = "Tab", mods = "LEADER|SHIFT", action = act.ActivateTabRelative(-1) },
    { key = "h", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
    { key = "j", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
    { key = "k", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
    { key = "l", mods = "LEADER", action = act.ActivatePaneDirection("Right") },
    { key = "v", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
    { key = "-", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
    { key = "x", mods = "LEADER", action = act.CloseCurrentPane({ confirm = true }) },
    { key = "g", mods = "LEADER", action = act.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES|TABS|DOMAINS" }) },
    { key = "d", mods = "LEADER", action = act.DetachDomain("CurrentPaneDomain") },

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

-- Remove inherited tab/pane window-manager shortcuts. The shared Leader table
-- above is the only effective path for these actions; non-WM defaults remain.
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
    { key = "T", mods = "CTRL" },
    { key = "T", mods = "SHIFT|CTRL" },
    { key = "W", mods = "CTRL" },
    { key = "Z", mods = "CTRL" },
    { key = "Z", mods = "SHIFT|CTRL" },
    { key = "[", mods = "SHIFT|SUPER" },
    { key = "]", mods = "SHIFT|SUPER" },
    { key = "^", mods = "CTRL" },
    { key = "^", mods = "SHIFT|CTRL" },
    { key = "t", mods = "SHIFT|CTRL" },
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
    { key = "LeftArrow", mods = "SHIFT|CTRL" },
    { key = "LeftArrow", mods = "SHIFT|ALT|CTRL" },
    { key = "RightArrow", mods = "SHIFT|CTRL" },
    { key = "RightArrow", mods = "SHIFT|ALT|CTRL" },
    { key = "UpArrow", mods = "SHIFT|CTRL" },
    { key = "UpArrow", mods = "SHIFT|ALT|CTRL" },
    { key = "DownArrow", mods = "SHIFT|CTRL" },
    { key = "DownArrow", mods = "SHIFT|ALT|CTRL" },
}

for _, binding in ipairs(default_window_manager_bindings) do
    table.insert(config.keys, {
        key = binding.key,
        mods = binding.mods,
        action = act.DisableDefaultAssignment,
    })
end

-- GUI window focus stays direct and does not conflict with Leader+h/l.
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
