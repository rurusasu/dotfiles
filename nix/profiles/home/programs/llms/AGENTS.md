# LLM/AI Tools Installation

This directory contains Nix configurations for installing LLM/AI coding tools.

## Installed Packages

| Package | Description |
|---------|-------------|
| `claude-code` | Anthropic's Claude Code CLI |
| `codex` | OpenAI Codex CLI |
| `gemini-cli` | Google Gemini CLI |
| `cursor-cli` | Cursor editor CLI |

## Configuration

Configurations for these tools are managed by chezmoi in `chezmoi/llms/`:
- `~/.claude/` - Claude Code settings
- `~/.codex/` - Codex configuration
- `~/.cursor/` - Cursor AI rules
- `~/.gemini/` - Gemini settings

## Notes

- Cursor editor is installed via `editors/cursor/`
