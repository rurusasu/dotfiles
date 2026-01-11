# LLMs Configuration

This directory contains configuration files for LLM/AI coding assistants.

## Structure

```
llms/
├── claude/           # Claude Code (Anthropic)
│   ├── settings.json # Claude Code settings
│   └── CLAUDE.md     # Global Claude instructions
├── codex/            # OpenAI Codex CLI
│   └── config.toml   # Codex configuration
├── cursor/           # Cursor AI
│   └── rules         # Cursor AI rules
└── gemini/           # Google Gemini
    └── settings.json # Gemini settings
```

## Deployment

Files are deployed to:
- `~/.claude/` - Claude Code
- `~/.codex/` - Codex CLI
- `~/.cursor/` - Cursor AI rules
- `~/.gemini/` - Gemini

## Installation

LLM tool binaries are installed via Nix (`nix/profiles/home/programs/llms/`):
- `claude-code` - Claude Code CLI
- `codex` - OpenAI Codex CLI
- `gemini-cli` - Google Gemini CLI
- `cursor-cli` - Cursor CLI

Cursor editor is installed via `editors/cursor/`.

## Notes

- CLAUDE.md contains global instructions that apply to all Claude Code sessions
- Cursor rules can also be project-specific via `.cursorrules` files
- Settings are cross-platform compatible
