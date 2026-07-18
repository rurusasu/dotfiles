# macOS nix-darwin One-command Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace imperative Homebrew/Home Manager setup with one `./install.sh` path that applies nix-darwin, nix-homebrew, Home Manager, Docker Desktop, chezmoi, and Compose.

**Architecture:** The shell script only bootstraps Command Line Tools and Nix, then invokes the pinned `.#darwin-rebuild` app. nix-darwin owns system activation, nix-homebrew owns Homebrew, and catalog-derived casks own GUI apps. Runtime setup remains a bounded post-switch phase.

**Tech Stack:** Bash, Bats, nix-darwin, nix-homebrew, Home Manager, Homebrew, Docker Desktop.

## Global Constraints

- Apple Silicon macOS 26+ is Full support.
- Homebrew casks are declarative; no normal-path direct `brew install --cask` or DMG fallback.
- The same command must pass twice.
- Docker Desktop personal-use license acceptance remains explicit.

---

### Task 1: Add the macOS nix-darwin configuration

**Files:**

- Create: `nix/darwin/default.nix`
- Create: `nix/flakes/darwin.nix`
- Modify: `nix/flakes/default.nix`
- Modify: `nix/home/common.nix`
- Test: `tests/bash/macos_config.bats`

**Interfaces:**

- Consumes: `sets.darwinCasks` and pinned flake inputs from the foundation plan.
- Produces: `darwinConfigurations.macos`.

- [ ] **Step 1: Write failing static/evaluation tests**

Add these tests:

```bash
@test "flake exposes a macOS nix-darwin configuration" {
  grep -q 'darwinConfigurations.macos' "$REPO_ROOT/nix/flakes/darwin.nix"
}

@test "Darwin uses nix-homebrew catalog casks and Home Manager" {
  grep -q 'nix-homebrew.enable = true' "$REPO_ROOT/nix/darwin/default.nix"
  grep -q 'casks = sets.darwinCasks' "$REPO_ROOT/nix/darwin/default.nix"
  grep -q 'home-manager.darwinModules.home-manager' "$REPO_ROOT/nix/flakes/darwin.nix"
}
```

- [ ] **Step 2: Verify RED**

Run: `bats tests/bash/macos_config.bats`

Expected: FAIL because the Darwin modules do not exist.

- [ ] **Step 3: Implement the Darwin module**

Create `nix/darwin/default.nix` with:

```nix
{ config, pkgs, lib, inputs, ... }:
let
  user = builtins.getEnv "DOTFILES_USER";
  home = builtins.getEnv "DOTFILES_HOME";
  sets = import ../packages/sets.nix {
    inherit pkgs lib;
    gwqSrc = inputs.gwq-src;
  };
in {
  assertions = [
    { assertion = user != ""; message = "DOTFILES_USER is required"; }
    { assertion = home != ""; message = "DOTFILES_HOME is required"; }
  ];
  system.primaryUser = user;
  system.stateVersion = 6;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    inherit user;
    autoMigrate = true;
  };
  homebrew = {
    enable = true;
    casks = sets.darwinCasks;
    onActivation = { autoUpdate = false; upgrade = false; cleanup = "none"; };
  };
  users.users.${user}.home = home;
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    users.${user} = import ../home/common.nix;
    extraSpecialArgs = { inherit inputs; };
  };
}
```

- [ ] **Step 4: Wire `darwinConfigurations.macos`**

Use `inputs.nix-darwin.lib.darwinSystem` with modules
`inputs.nix-homebrew.darwinModules.nix-homebrew`,
`inputs.home-manager.darwinModules.home-manager`, and `../darwin/default.nix`.

- [ ] **Step 5: Verify the build**

Run:

```bash
DOTFILES_USER="$USER" DOTFILES_HOME="$HOME" nix build .#darwinConfigurations.macos.system --impure --no-link
bats tests/bash/macos_config.bats
```

Expected: build and tests exit 0.

- [ ] **Step 6: Commit**

```bash
git add nix/darwin nix/flakes/darwin.nix nix/flakes/default.nix nix/home/common.nix tests/bash/macos_config.bats
git commit -m "feat: add nix-darwin system configuration"
```

### Task 2: Refactor the macOS installer around nix-darwin

**Files:**

- Create: `scripts/sh/install-common.sh`
- Modify: `scripts/sh/install-macos.sh`
- Test: `tests/bash/install_macos.bats`

**Interfaces:**

- Produces functions `dotfiles_log`, `dotfiles_die`, `dotfiles_have`, `dotfiles_wait_for`, `dotfiles_load_nix`, `dotfiles_link_checkout`.
- Invokes: `nix run .#darwin-rebuild -- switch --flake .#macos --impure`.

- [ ] **Step 1: Replace old expectations with failing nix-darwin expectations**

Add assertions to the fresh-install and installed-prerequisites cases:

```bash
grep -q 'nix run .#darwin-rebuild -- switch --flake .#macos --impure' "$COMMAND_LOG"
! grep -q 'brew install --cask' "$COMMAND_LOG"
! grep -q 'desktop.docker.com/mac' "$COMMAND_LOG"
[ "$(grep -c 'nixos.org/nix/install' "$COMMAND_LOG" || true)" -le 1 ]
```

- [ ] **Step 2: Verify RED**

Run: `bats tests/bash/install_macos.bats`

Expected: FAIL because the current script directly installs Homebrew/Docker and standalone Home Manager.

- [ ] **Step 3: Extract common bootstrap helpers**

Implement helpers with these signatures:

```bash
dotfiles_log() { printf '\033[1;34m[%s]\033[0m %s\n' "$DOTFILES_LOG_PREFIX" "$*"; }
dotfiles_die() { printf '\033[1;31m[%s]\033[0m %s\n' "$DOTFILES_LOG_PREFIX" "$*" >&2; exit 1; }
dotfiles_have() { command -v "$1" >/dev/null 2>&1; }
dotfiles_load_nix() { [ ! -r "$DOTFILES_NIX_PROFILE_SCRIPT" ] || . "$DOTFILES_NIX_PROFILE_SCRIPT"; }
```

Move the existing safe checkout backup/link behavior without changing semantics.

- [ ] **Step 4: Implement the minimal Darwin switch flow**

The main order must be:

```bash
preflight
ensure_command_line_tools
ensure_nix
dotfiles_link_checkout "$ROOT"
export DOTFILES_USER="${SUDO_USER:-$USER}"
export DOTFILES_HOME="$HOME"
export DOTFILES_ROOT="$ROOT"
(cd "$ROOT" && nix run .#darwin-rebuild -- switch --flake .#macos --impure)
setup_docker_runtime
apply_chezmoi
start_hermes_stack
verify_environment --runtime
```

Delete `ensure_homebrew`, direct cask installation, DMG fallback, and standalone Home Manager activation.

- [ ] **Step 5: Verify GREEN and shell quality**

Run:

```bash
bash -n scripts/sh/install-common.sh scripts/sh/install-macos.sh
bats tests/bash/install_macos.bats
nix fmt -- --fail-on-change
```

Expected: all commands exit 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/sh/install-common.sh scripts/sh/install-macos.sh tests/bash/install_macos.bats
git commit -m "feat: converge macOS with nix-darwin"
```

### Task 3: Add shared runtime acceptance

**Files:**

- Create: `scripts/sh/verify-environment.sh`
- Test: `tests/bash/verify_environment.bats`
- Modify: `scripts/sh/install-macos.sh`

**Interfaces:**

- Produces CLI: `verify-environment.sh [--runtime]`.
- Returns nonzero on any required missing tool, Docker failure, chezmoi drift, or Compose health failure.

- [ ] **Step 1: Write failing acceptance tests**

Add these concrete cases:

```bash
@test "missing required command fails verification" {
  rm "$STUB_BIN/nvim"
  run "$VERIFIER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing command: nvim"* ]]
}

@test "runtime verification exercises Docker" {
  run "$VERIFIER" --runtime
  [ "$status" -eq 0 ]
  grep -q '^docker run --rm hello-world$' "$COMMAND_LOG"
}
```

- [ ] **Step 2: Verify RED**

Run: `bats tests/bash/verify_environment.bats`

Expected: FAIL because the verifier is absent.

- [ ] **Step 3: Implement exact required checks**

```bash
required=(nix brew darwin-rebuild git gh chezmoi rg fd jq nvim node python3 go rustup docker)
for command_name in "${required[@]}"; do
  command -v "$command_name" >/dev/null 2>&1 || fail "missing command: $command_name"
done
docker compose version >/dev/null
chezmoi apply --dry-run >/dev/null
docker info >/dev/null
if [ "$runtime" -eq 1 ]; then
  docker run --rm hello-world >/dev/null
  docker compose -f "$COMPOSE_FILE" config >/dev/null
  docker compose -f "$COMPOSE_FILE" ps --status running >/dev/null
fi
```

- [ ] **Step 4: Verify and commit**

Run: `bats tests/bash/verify_environment.bats tests/bash/install_macos.bats`

Expected: PASS.

```bash
git add scripts/sh/verify-environment.sh scripts/sh/install-macos.sh tests/bash/verify_environment.bats
git commit -m "test: verify the installed macOS environment"
```
