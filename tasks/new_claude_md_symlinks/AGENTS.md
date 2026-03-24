# AGENTS

Purpose: Create CLAUDE.md symlinks pointing to AGENTS.md in all directories.

📖 **詳細ドキュメント**: [docs/taskfile/new_claude_md_symlinks.md](../../docs/taskfile/new_claude_md_symlinks.md)

## Background

Claude Code reads `CLAUDE.md` files for project instructions, while `AGENTS.md` is the standard convention for AI agent instructions. This task creates symlinks so both tools can use the same instruction files.

## Usage

From repository root (`D:\program\dotfiles`):

```powershell
# Show available commands
task symlinks

# Windows - Create symlinks
task symlinks:create

# Windows - Preview (dry-run)
task symlinks:dry-run

# WSL/Linux - Create symlinks
task symlinks:create:wsl

# WSL/Linux - Preview (dry-run)
task symlinks:dry-run:wsl
```

## Files

| File                        | Description                  |
| --------------------------- | ---------------------------- |
| `Taskfile.yml`              | Task definitions             |
| `New-ClaudeMdSymlinks.ps1`  | PowerShell script (Windows)  |
| `new-claude-md-symlinks.sh` | Shell script (Linux/Mac/WSL) |

## Behavior

1. Finds all `AGENTS.md` files in the repository
2. Creates `CLAUDE.md` symlinks pointing to `AGENTS.md` in the same directory
3. Skips directories where `CLAUDE.md` already exists as a regular file (e.g., `chezmoi/dot_claude/CLAUDE.md`)
4. Re-creates symlinks if they already exist

## Windows Notes

Symlink creation may fail without proper permissions. Solutions:

1. **Enable Developer Mode** (recommended)
   - Settings > Update & Security > For developers > Developer Mode

2. **Run as Administrator**
   - Right-click terminal and select "Run as administrator"

## Git Integration

- `CLAUDE.md` files are in `.gitignore` (except `chezmoi/dot_claude/CLAUDE.md`)
- Symlinks are created locally after clone via `task symlinks:create`
