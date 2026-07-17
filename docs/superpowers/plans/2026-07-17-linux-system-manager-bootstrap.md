# Linux and NixOS One-command Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `./install.sh` fully configure NixOS, Ubuntu, and Debian, while requiring explicit opt-in for user-only fallback on other Linux distributions.

**Architecture:** A thin dispatcher selects NixOS rebuild, System Manager, or standalone Home Manager. Ubuntu/Debian use the same System Manager module with host metadata passed by environment, and activate Home Manager in the same switch. Docker is a systemd service/socket managed by the system layer.

**Tech Stack:** Bash, Bats, NixOS modules, System Manager, Home Manager, systemd, Docker.

## Global Constraints

- Full support requires systemd on Ubuntu/Debian.
- Other Linux must fail unless `DOTFILES_ALLOW_USER_ONLY=1` is set.
- The current user is not silently replaced or recreated with a different UID/GID.
- Docker and Compose runtime checks are mandatory for Full support.

---

### Task 1: Expand the POSIX platform dispatcher

**Files:**

- Modify: `install.sh`
- Modify: `tests/bash/install_dispatcher.bats`
- Create: `scripts/sh/install-nixos.sh`
- Create: `scripts/sh/install-linux.sh`
- Create: `scripts/sh/install-home-manager.sh`

**Interfaces:**

- Produces routing targets for `Darwin`, NixOS, Ubuntu, Debian, unsupported Linux, and Windows-like shells.

- [ ] **Step 1: Add failing routing tests**

Add stubs for `/etc/os-release` through `DOTFILES_OS_RELEASE_FILE` and test:

```bash
TEST_UNAME_S=Linux TEST_UNAME_M=x86_64 DOTFILES_NIXOS_MARKER="$marker" ./install.sh --example
TEST_UNAME_S=Linux DOTFILES_OS_RELEASE_FILE="$ubuntu_release" ./install.sh --example
TEST_UNAME_S=Linux DOTFILES_OS_RELEASE_FILE="$debian_release" ./install.sh --example
DOTFILES_ALLOW_USER_ONLY=1 TEST_UNAME_S=Linux DOTFILES_OS_RELEASE_FILE="$fedora_release" ./install.sh
```

Require unsupported Linux without opt-in to exit nonzero and mention `DOTFILES_ALLOW_USER_ONLY=1`.

- [ ] **Step 2: Verify RED**

Run: `bats tests/bash/install_dispatcher.bats`

Expected: Linux cases fail because `install.sh` only supports Apple Silicon macOS.

- [ ] **Step 3: Implement minimal routing**

```bash
case "$os" in
  Darwin) exec "$ROOT/scripts/sh/install-macos.sh" "$@" ;;
  Linux)
    if [ -e "${DOTFILES_NIXOS_MARKER:-/etc/NIXOS}" ]; then
      exec "$ROOT/scripts/sh/install-nixos.sh" "$@"
    fi
    . "${DOTFILES_OS_RELEASE_FILE:-/etc/os-release}"
    case "${ID:-}" in
      ubuntu|debian) exec "$ROOT/scripts/sh/install-linux.sh" "$@" ;;
      *)
        [ "${DOTFILES_ALLOW_USER_ONLY:-0}" = 1 ] || {
          printf 'Unsupported Linux. Set DOTFILES_ALLOW_USER_ONLY=1 for Home Manager only.\n' >&2
          exit 1
        }
        exec "$ROOT/scripts/sh/install-home-manager.sh" "$@"
        ;;
    esac
    ;;
  MINGW*|MSYS*|CYGWIN*) printf 'Windows setup uses install.cmd.\n' >&2; exit 1 ;;
esac
```

- [ ] **Step 4: Verify and commit**

Run: `bash -n install.sh scripts/sh/install-*.sh && bats tests/bash/install_dispatcher.bats`

Expected: PASS.

```bash
git add install.sh scripts/sh/install-nixos.sh scripts/sh/install-linux.sh scripts/sh/install-home-manager.sh tests/bash/install_dispatcher.bats
git commit -m "feat: route one-command setup across Linux systems"
```

### Task 2: Add Ubuntu/Debian System Manager outputs

**Files:**

- Create: `nix/system-manager/default.nix`
- Create: `nix/system-manager/docker.nix`
- Create: `nix/flakes/system-manager.nix`
- Modify: `nix/flakes/default.nix`
- Test: `tests/bash/linux_config.bats`

**Interfaces:**

- Consumes: `DOTFILES_USER`, `DOTFILES_HOME`, UID/GID environment values.
- Produces: `systemConfigs.ubuntu` and `systemConfigs.debian`.

- [ ] **Step 1: Write failing module tests**

Add these tests:

```bash
@test "flake exposes Ubuntu and Debian System Manager configs" {
  grep -q 'ubuntu = mkConfig' "$REPO_ROOT/nix/flakes/system-manager.nix"
  grep -q 'debian = mkConfig' "$REPO_ROOT/nix/flakes/system-manager.nix"
}

@test "System Manager integrates Home Manager Nix and Docker" {
  grep -q 'home-manager.nixosModules.home-manager' "$REPO_ROOT/nix/flakes/system-manager.nix"
  grep -q 'nix.enable = true' "$REPO_ROOT/nix/system-manager/default.nix"
  grep -q 'systemd.services.docker' "$REPO_ROOT/nix/system-manager/docker.nix"
  grep -q 'systemd.sockets.docker' "$REPO_ROOT/nix/system-manager/docker.nix"
  grep -q 'docker-buildx' "$REPO_ROOT/nix/system-manager/docker.nix"
}
```

- [ ] **Step 2: Verify RED**

Run: `bats tests/bash/linux_config.bats`

Expected: FAIL because System Manager files are absent.

- [ ] **Step 3: Implement the shared system module**

Use the existing user; do not assign fixed IDs:

```nix
{ pkgs, lib, inputs, ... }:
let
  user = builtins.getEnv "DOTFILES_USER";
  home = builtins.getEnv "DOTFILES_HOME";
  uid = lib.toInt (builtins.getEnv "DOTFILES_UID");
  gid = lib.toInt (builtins.getEnv "DOTFILES_GID");
in {
  nix.enable = true;
  services.userborn.enable = true;
  users.groups.${user}.gid = gid;
  users.groups.docker = { };
  users.users.${user} = {
    isNormalUser = true;
    inherit uid home;
    group = user;
    extraGroups = [ "docker" ];
  };
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-backup";
    users.${user} = import ../home/common.nix;
    extraSpecialArgs = { inherit inputs; };
  };
}
```

Implement `docker.nix` from the official System Manager pattern with `docker`, `docker-compose`,
`docker-buildx`, `/etc/docker/daemon.json`, `docker.service`, `docker.socket`, and tmpfiles. Socket group
must be `docker`; service must be wanted by `system-manager.target`.

- [ ] **Step 4: Wire named configs**

```nix
system = let requested = builtins.getEnv "DOTFILES_SYSTEM"; in
  if requested == "" then "x86_64-linux" else requested;
mkConfig = inputs.system-manager.lib.makeSystemConfig {
  modules = [
    inputs.home-manager.nixosModules.home-manager
    { nixpkgs.hostPlatform = system; }
    ../system-manager/default.nix
    ../system-manager/docker.nix
  ];
};
flake.systemConfigs = {
  ubuntu = mkConfig;
  debian = mkConfig;
};
```

- [ ] **Step 5: Build and commit**

Run:

```bash
DOTFILES_USER="$USER" DOTFILES_HOME="$HOME" DOTFILES_UID="$(id -u)" DOTFILES_GID="$(id -g)" DOTFILES_SYSTEM=x86_64-linux nix build .#systemConfigs.ubuntu --impure --no-link
bats tests/bash/linux_config.bats
```

Expected: build and tests pass.

```bash
git add nix/system-manager nix/flakes/system-manager.nix nix/flakes/default.nix tests/bash/linux_config.bats
git commit -m "feat: manage Ubuntu and Debian with System Manager"
```

### Task 3: Implement the generic Linux bootstrap

**Files:**

- Modify: `scripts/sh/install-linux.sh`
- Modify: `scripts/sh/install-home-manager.sh`
- Test: `tests/bash/install_linux.bats`

**Interfaces:**

- Invokes: `nix run .#system-manager -- switch --flake .#ubuntu|debian --sudo --impure`.
- Invokes fallback: Home Manager activation package only after explicit opt-in.

- [ ] **Step 1: Write failing phase/idempotency tests**

Require Nix install only when absent, exact System Manager config selection, environment propagation,
chezmoi/Compose/acceptance ordering, and second-run no reinstall.

- [ ] **Step 2: Verify RED**

Run: `bats tests/bash/install_linux.bats`

Expected: FAIL because scripts are empty dispatch targets.

- [ ] **Step 3: Implement the Full support flow**

```bash
ensure_systemd
ensure_nix
dotfiles_link_checkout "$ROOT"
export DOTFILES_USER="${SUDO_USER:-$USER}"
export DOTFILES_HOME="$HOME"
export DOTFILES_UID="$(id -u "$DOTFILES_USER")"
export DOTFILES_GID="$(id -g "$DOTFILES_USER")"
export DOTFILES_SYSTEM="$(nix eval --impure --raw --expr builtins.currentSystem)"
config="$(. /etc/os-release; printf '%s' "$ID")"
(cd "$ROOT" && nix run .#system-manager -- switch --flake ".#$config" --sudo --impure)
apply_chezmoi
start_hermes_stack
run_as_docker_group "$ROOT/scripts/sh/verify-environment.sh" --runtime
```

Validate that user/home/UID/GID are nonempty numeric values before invoking Nix.

- [ ] **Step 4: Implement explicit Home Manager fallback**

Build `.#homeConfigurations.${DOTFILES_SYSTEM}.activationPackage --impure`, run `activate`, apply chezmoi,
and print `User-only setup complete; Docker/systemd were not configured.` Do not invoke runtime acceptance.

- [ ] **Step 5: Verify and commit**

Run: `bash -n scripts/sh/install-linux.sh scripts/sh/install-home-manager.sh && bats tests/bash/install_linux.bats`

Expected: PASS.

```bash
git add scripts/sh/install-linux.sh scripts/sh/install-home-manager.sh tests/bash/install_linux.bats
git commit -m "feat: bootstrap Ubuntu and Debian in one command"
```

### Task 4: Converge native NixOS through the same acceptance path

**Files:**

- Modify: `scripts/sh/install-nixos.sh`
- Modify: `nix/hosts/linux/configuration.nix`
- Test: `tests/bash/install_nixos.bats`

**Interfaces:**

- Invokes `sudo nixos-rebuild switch --flake "$ROOT#linux" --impure`.
- Reuses `verify-environment.sh --runtime`.

- [ ] **Step 1: Add failing NixOS orchestration tests**

Add this primary test and companion nonzero-status cases for rebuild, Compose, and verification:

```bash
@test "NixOS rebuilds then applies chezmoi Compose and acceptance" {
  run "$INSTALLER"
  [ "$status" -eq 0 ]
  grep -q 'nixos-rebuild switch --flake .*#linux --impure' "$COMMAND_LOG"
  [ "$(line_of nixos-rebuild)" -lt "$(line_of chezmoi)" ]
  [ "$(line_of chezmoi)" -lt "$(line_of 'docker compose')" ]
  [ "$(line_of 'docker compose')" -lt "$(line_of verify-environment)" ]
}
```

- [ ] **Step 2: Verify RED**

Run: `bats tests/bash/install_nixos.bats`

Expected: FAIL because `install-nixos.sh` has no implementation.

- [ ] **Step 3: Implement and ensure Docker module completeness**

Use the same exported metadata as Linux, call `nixos-rebuild`, then run chezmoi, Compose, and runtime
verification. Ensure `virtualisation.docker.enable`, Compose/Buildx packages, and docker group membership are
present in `nix/hosts/linux/configuration.nix`.

- [ ] **Step 4: Verify and commit**

Run:

```bash
bats tests/bash/install_nixos.bats
nix build .#nixosConfigurations.linux.config.system.build.toplevel --no-link
```

Expected: PASS.

```bash
git add scripts/sh/install-nixos.sh nix/hosts/linux/configuration.nix tests/bash/install_nixos.bats
git commit -m "feat: converge NixOS through one-command setup"
```
