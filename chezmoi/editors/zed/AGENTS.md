# Zed Configuration

Zed is a high-performance, native code editor.

## Documentation

- [Extensions](../../../docs/editors/zed/extensions.md) - 拡張機能管理の詳細

## Files

| File            | Deployed To                          | Purpose            |
| --------------- | ------------------------------------ | ------------------ |
| `settings.json` | `~/.config/zed/` or `%APPDATA%/Zed/` | Editor settings    |
| `keymap.json`   | Same as above                        | Custom keybindings |

## Key Settings

- Format: JSONC (JSON with comments)
- Theme: GitHub Dark Dimmed
- Vim mode: Disabled
- Tab size: 2 spaces
- Format on save: Enabled

## Tab Width Limitation

- Zed currently does not provide a setting equivalent to VS Code/Cursor `workbench.editor.tabSizing = fixed`.
- File tab width (pixel width) cannot be forced to a uniform fixed value.
- Available alternatives are visual stabilization settings (for example `max_tabs`, `tabs.show_close_button`, icon/status visibility).

## Extensions

`auto_install_extensions` で宣言的に管理。`true` で自動インストール、`false` で禁止。

**現在の拡張機能**: github-theme, powershell, nix, toml, dprint, lua, oxc

## Language Formatters

| Language              | Formatter       |
| --------------------- | --------------- |
| JavaScript/TypeScript | oxfmt           |
| TOML                  | taplo           |
| Markdown              | dprint          |
| Lua                   | stylua          |
| Nix                   | nixfmt          |
| Shell Script          | shfmt           |
| PowerShell            | language_server |

## Installation

- **Linux/WSL**: `nix` (zed-editor package)
- **Windows**: `winget install Zed.Zed`
