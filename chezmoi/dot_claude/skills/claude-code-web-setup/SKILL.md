---
name: claude-code-web-setup
description: |
  Set up Claude Code on the Web (claude.ai/code) cloud environments for repositories.
  Use when:
  - Creating a new cloud environment for a GitHub repository
  - Debugging setup script failures on claude.ai/code
  - Configuring environment variables and setup scripts for cloud VMs
  - Fixing "No such file or directory" errors in setup scripts
  Triggers: "claude code web", "cloud environment", "claude.ai/code setup", "remote environment", "web CC setup", "クラウド環境", "リモート環境構築"
---

# Claude Code on the Web - Cloud Environment Setup

Details in `references/` and templates in `templates/`.

## Quick Reference

- VM architecture & common errors → `references/cloud-vm-architecture.md`
- Setup script patterns & pitfalls → `references/setup-patterns.md`
- UI operations (create/edit/debug) → `references/ui-operations.md`
- `setup.sh` template → `templates/setup.sh.template`

## Workflow

1. Create `setup.sh` in repo root (use `templates/setup.sh.template`)
2. Push to GitHub
3. Create cloud environment in claude.ai/code (see `references/ui-operations.md`)
4. Set cloud setup script to find + run repo's `setup.sh` (see `references/setup-patterns.md`)
5. Test with verification task
