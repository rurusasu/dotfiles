# bun → pnpm + Node.js Migration Design

## Goal

Replace all bun dependencies across the dotfiles repository with pnpm + Node.js, establishing a consistent runtime stack.

## Scope

All bun references across: MCP server config, Windows/NixOS package management, PowerShell handlers and profile, Docker (openclaw), Taskfile, and shell scripts.

## Key Decisions

- **MCP servers**: `bunx -y <pkg>` → `pnpm dlx <pkg>` (drop `-y` flag; pnpm dlx doesn't need it)
- **Docker home directory**: `/home/bun` → `/home/app` (remove bun naming)
- **pnpm activation in Docker**: Use `corepack enable` (Node.js 22 ships corepack)
- **Global packages (Windows)**: `pnpm add -g`, bin path via `pnpm bin -g` (typically `%LOCALAPPDATA%/pnpm`)
- **PowerShell CLI shims**: Use `node` + entrypoint instead of `bun` + entrypoint

## Changes

### 1. MCP Servers (`chezmoi/.chezmoidata/mcp_servers.yaml`)

- Replace `bunx` → `pnpm dlx` in command field (8 servers)
- Remove `-y` from args (first arg of each)

### 2. Package Lists

- Move `windows/bun/packages.json` → `windows/pnpm/packages.json`
- Move `nix/bun/packages.json` → `nix/pnpm/packages.json`
- Update description field in both

### 3. PowerShell Handler

- Replace `Handler.Bun.ps1` → `Handler.Pnpm.ps1`
- Replace `Handler.Bun.Tests.ps1` → `Handler.Pnpm.Tests.ps1`
- Class: `PnpmHandler` (Order=7, uses `pnpm add -g`)
- Remove: bunx.cmd shim creation (pnpm dlx is built-in)
- Remove: AddBunBinToPath (replace with pnpm global bin path)
- Update: IsPackageInstalled to check pnpm global node_modules
- Update: gemini shim to use `node` instead of `bun`
- Add `Invoke-Pnpm` function, remove `Invoke-Bun`

### 4. PowerShell Profile (`chezmoi/shells/Microsoft.PowerShell_profile.ps1`)

- Replace bun global CLI shims section
- Use pnpm global modules path (`~/.local/share/pnpm/global/5/node_modules` or output of `pnpm root -g`)
- Change `bun` → `node` in function shims

### 5. Docker (`docker/openclaw/`)

- **Dockerfile**: Remove bun install, add `corepack enable && corepack prepare pnpm@latest --activate`. Install qmd via `pnpm install -g`. Change `/home/bun` → `/home/app`.
- **docker-compose.yml**: Change all `/home/bun` → `/home/app`. Remove `BUN_INSTALL` env. Update PATH to remove bun paths. Replace `tmpfs /home/bun/.agents` → `/home/app/.agents`.
- **entrypoint.sh**: Change all `/home/bun` → `/home/app`.
- **README.md**: Update path references.

### 6. Taskfile (`Taskfile.yml`)

- Remove `--build-arg INSTALL_BUN=1` from sandbox build
- Remove `/app/data/workspace/.cache/bun` from cache init/clean

### 7. Shell Script (`check_nixos.sh`)

- Replace `bun` → `pnpm` in tool check list

### 8. Invoke-ExternalCommand.ps1

- Remove `Invoke-Bun` function
- Add `Invoke-Pnpm` function
