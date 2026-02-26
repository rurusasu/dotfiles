# Claude Code Configuration

This directory contains Claude Code settings and global instructions.

## Files

- `settings.json` - Claude Code application settings
- `CLAUDE.md` - Global instructions for Claude Code sessions
- `agents/` - Claude Code subagents (`~/.claude/agents/`)
- `plugins/` - Claude Code plugins
  - `run_onchange_install-superpowers.ps1` - Plugin installer script
  - `superpowers/` - Superpowers plugin directory

## CLAUDE.md

The CLAUDE.md file contains persistent instructions that apply to all Claude Code sessions. Use it for:

- Preferred coding style and conventions
- Project-independent guidelines
- Common patterns and preferences

## Deployment

Deployed to `~/.claude/` via chezmoi on all platforms.

## Installation

| Platform | Method     | Config                                                               |
| -------- | ---------- | -------------------------------------------------------------------- |
| NixOS    | Nix flakes | [`nix/core/cli.nix`](../../nix/core/cli.nix)                         |
| Windows  | winget     | [`windows/winget/packages.json`](../../windows/winget/packages.json) |
