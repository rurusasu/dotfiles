# WezTerm macOS leader pane keybindings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOSのWezTerm pane/window操作からOption+Shiftを外し、Ctrl+Space leader方式へ統一する。

**Architecture:** WezTermの既存leader (`Ctrl+Space`) をpane split/navigation/resize/window focusの接頭辞として再利用する。Windows TerminalのWindows標準bindingとAlt単独のshell widget、既存のpane close/zoomは変更しない。

**Tech Stack:** WezTerm Lua configuration, chezmoi terminal deployment, Markdown documentation, pre-commit/treefmt.

## Global Constraints

- macOSのWezTermではOption+Shiftをpane/window操作に使わない。
- 右分割は `Ctrl+Space` → `|`、下分割は `Ctrl+Space` → `-`。
- pane移動はleader + 矢印、サイズ変更はleader + Shift + 矢印。
- WezTerm window focusはleader + h/l。
- `Ctrl+Shift+w`、`Ctrl+Alt+w`、tab操作、Alt単独のshell widgetは維持する。
- Windows Terminal設定は変更しない。

---

### Task 1: Update WezTerm macOS leader bindings

**Files:**

- Modify: `chezmoi/terminals/wezterm/wezterm.lua:118-145`

**Interfaces:**

- Consumes: existing `config.leader`, `act.SplitHorizontal`, `act.SplitVertical`, `act.ActivatePaneDirection`, `act.AdjustPaneSize`, and `focus_adjacent_window`.
- Produces: leader-based pane and WezTerm-window actions used by the deployed macOS config.

- [ ] Remove the `ALT|SHIFT` split, navigation, window-focus, and resize assignments.
- [ ] Add these mappings:

```lua
{ key = "|", mods = "LEADER", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
{ key = "-", mods = "LEADER", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
{ key = "LeftArrow", mods = "LEADER", action = act.ActivatePaneDirection("Left") },
{ key = "UpArrow", mods = "LEADER", action = act.ActivatePaneDirection("Up") },
{ key = "RightArrow", mods = "LEADER", action = act.ActivatePaneDirection("Right") },
{ key = "DownArrow", mods = "LEADER", action = act.ActivatePaneDirection("Down") },
{ key = "LeftArrow", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Left", 5 }) },
{ key = "UpArrow", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Up", 5 }) },
{ key = "RightArrow", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Right", 5 }) },
{ key = "DownArrow", mods = "LEADER|SHIFT", action = act.AdjustPaneSize({ "Down", 5 }) },
{ key = "h", mods = "LEADER", action = focus_adjacent_window("left") },
{ key = "l", mods = "LEADER", action = focus_adjacent_window("right") },
```

- [ ] Preserve the existing close, zoom, tab, Alt-only shell, and leader Backspace assignments.
- [ ] Run `wezterm ls-fonts >/dev/null` and `wezterm show-keys --lua` to confirm the Lua config loads and new leader mappings exist.

### Task 2: Synchronize keybinding documentation

**Files:**

- Modify: `docs/chezmoi/keybindings.md:11-45`

**Interfaces:**

- Consumes: the implemented WezTerm bindings and the unchanged Windows Terminal bindings.
- Produces: documentation that distinguishes macOS WezTerm leader operations from Windows Terminal Alt operations.

- [ ] Change the shared GUI pane rules to describe the platform-specific split.
- [ ] Replace WezTerm’s Alt/Alt+Shift pane and window entries with the leader mappings.
- [ ] Keep Windows Terminal entries unchanged.
- [ ] Run `git diff --check` and the repository pre-commit hooks for the modified files.

### Task 3: Deploy and verify

**Files:**

- Deploy: `~/.config/wezterm/wezterm.lua` from `chezmoi/terminals/wezterm/wezterm.lua`

**Interfaces:**

- Consumes: the source WezTerm Lua configuration.
- Produces: a deployed configuration with matching SHA-256 content.

- [ ] Render and execute the terminal-only chezmoi deploy script using the main source directory.
- [ ] Verify source and deployed WezTerm configs have identical SHA-256 hashes.
- [ ] Verify `wezterm show-keys --lua` contains leader split, navigation, resize, and window-focus mappings and no `ALT|SHIFT` pane mappings.
- [ ] Fully restart the WezTerm app if automatic reload is unavailable.
- [ ] Manually test split, navigation, resize, window focus, and Delete after an incorrect leader key.

### Task 4: Commit implementation

**Files:**

- Commit: `chezmoi/terminals/wezterm/wezterm.lua`, `docs/chezmoi/keybindings.md`

- [ ] Review the final diff for unrelated changes.
- [ ] Commit with a focused message: `fix: use leader for macOS WezTerm pane controls`.
