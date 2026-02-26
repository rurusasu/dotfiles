# Cursor AI Configuration

This directory contains Cursor AI editor configuration.

## Files

- `rules` - Global Cursor AI rules
- `cli-config.json` - Cursor CLI configuration

## Rules

The rules file contains instructions that apply to all Cursor AI sessions. Project-specific rules can be added via `.cursorrules` files in project directories.

## CLI Configuration

`cli-config.json` configures Cursor CLI behavior. See [Cursor CLI docs](https://cursor.com/docs/cli/reference/configuration).

| Setting          | Value   | Description                           |
| ---------------- | ------- | ------------------------------------- |
| `model`          | `auto`  | Auto-select model                     |
| `editor.vimMode` | `false` | Vim keybindings disabled              |
| `attribution.*`  | `true`  | Show agent attribution on commits/PRs |

### Permissions

Permissions follow Claude Code settings (`dot_claude/settings.json`).

**Allow:** `Read(**/*)`、`Write(**/*)`、`Shell(*)`

**Deny:**

| Category           | Rules                                                                |
| ------------------ | -------------------------------------------------------------------- |
| Dangerous commands | `Shell(sudo)`, `Shell(curl)`, `Shell(wget)`, `Shell(rm)`             |
| Environment files  | `Read/Write(.env*)`                                                  |
| Secrets            | `Read/Write(secrets/**)`                                             |
| SSH keys           | `Read(**/*id_rsa*)`, `Read(**/*id_ed25519*)`                         |
| Certificates       | `Read/Write(**/*.pem)`, `Read/Write(**/*.key)`                       |
| Dependencies       | `Write(pyproject.toml)`, `Write(requirements.txt)`, `Write(uv.lock)` |

## Deployment

Deployed to `~/.cursor/` via chezmoi on all platforms.

## Installation

Cursor editor is installed via:

| Platform | Method | Config                                       |
| -------- | ------ | -------------------------------------------- |
| Windows  | winget | [`editors/cursor/`](../editors/cursor/)      |
| NixOS    | Nix    | [`nix/core/cli.nix`](../../nix/core/cli.nix) |
