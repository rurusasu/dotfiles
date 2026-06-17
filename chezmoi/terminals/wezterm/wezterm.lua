local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()

-- Window focus: h=left, l=right
-- Same-process: WezTerm native. Cross-process: Win32 SetForegroundWindow via PowerShell.
local function focus_adjacent_window(direction)
    return wezterm.action_callback(function(window, pane)
        local wins = wezterm.gui.gui_windows()
        table.sort(wins, function(a, b) return a:window_id() < b:window_id() end)
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
            "[DllImport(\"user32\")]public static extern IntPtr GetForegroundWindow();",
            "[DllImport(\"user32\")]public static extern bool SetForegroundWindow(IntPtr h);",
            "[DllImport(\"user32\")]public static extern bool ShowWindow(IntPtr h,int n);",
            "[DllImport(\"user32\")]public static extern bool IsIconic(IntPtr h);}';",
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
config.leader = {
    key = "Space",
    mods = "CTRL",
    timeout_milliseconds = 2000,
}

-- Force snacks.nvim to recognise WezTerm's Kitty graphics protocol support.
-- Auto-detection can fail on Windows where TERM_PROGRAM may not propagate.
config.set_environment_variables = {
    SNACKS_WEZTERM = "true",
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

    -- Window focus (Ctrl+Alt+Shift + H/L)
    { key = "h", mods = "CTRL|ALT|SHIFT", action = focus_adjacent_window("left") },
    { key = "l", mods = "CTRL|ALT|SHIFT", action = focus_adjacent_window("right") },

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

    -- Disable default font size bindings except Ctrl+Shift+{+/-/0}
    { key = "+", mods = "CTRL", action = act.DisableDefaultAssignment },
    { key = "-", mods = "CTRL", action = act.DisableDefaultAssignment },
    { key = "=", mods = "CTRL", action = act.DisableDefaultAssignment },
    { key = "0", mods = "CTRL", action = act.DisableDefaultAssignment },
    { key = "=", mods = "CTRL|SHIFT", action = act.DisableDefaultAssignment },
    { key = "\\", mods = "CTRL|SHIFT", action = act.DisableDefaultAssignment },
    { key = "w", mods = "CTRL|SHIFT", action = act.DisableDefaultAssignment },

    -- Font size via Ctrl+Shift+{+/-/0}
    { key = "+", mods = "CTRL|SHIFT", action = act.IncreaseFontSize },
    { key = "-", mods = "CTRL|SHIFT", action = act.DecreaseFontSize },
    { key = "0", mods = "CTRL|SHIFT", action = act.ResetFontSize },

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
