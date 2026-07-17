# macOS Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-command Apple Silicon macOS installer that provisions Homebrew, Docker Desktop, Nix, Home Manager, chezmoi, and the existing Hermes Docker Compose stack.

**Architecture:** A root `install.sh` performs platform dispatch, while `scripts/sh/install-macos.sh` owns idempotent provisioning phases. Bats tests execute the scripts against stub commands and a temporary HOME, and the existing Home Manager package catalog plus Docker Compose file remain the configuration sources of truth.

**Tech Stack:** Bash 3.2-compatible shell, Bats, Nix flakes, Home Manager, chezmoi, Homebrew, Docker Desktop, Docker Compose.

## Global Constraints

- Support Apple Silicon and macOS 26 or later only.
- Keep `install.cmd` as the Windows entry point.
- Use Docker Desktop and the existing `docker/hermes-agent/compose.yml`; do not add Apple `container`, Colima, Podman, or OrbStack fallback.
- Use `--impure` for Home Manager evaluation because `nix/home/common.nix` reads `USER` and `HOME` with `builtins.getEnv`.
- Never delete an existing `~/.dotfiles`; move conflicts to `~/.dotfiles.backup.<timestamp>`.
- Do not run `brew update`, `docker system prune`, delete Docker volumes, or perform registry login.
- All waits must be bounded and the installer must be safe to rerun after partial failure.
- The Docker Desktop license is accepted for the user's stated personal use.

---

## File Structure

- Create `install.sh`: macOS/arm64 dispatcher and unsupported-platform guidance.
- Create `scripts/sh/install-macos.sh`: provisioning orchestration and bounded readiness checks.
- Create `tests/bash/install_dispatcher.bats`: dispatcher behavior.
- Create `tests/bash/install_macos.bats`: end-to-end stubbed provisioning behavior.
- Create `tests/bash/macos_config.bats`: static Home Manager, Compose, README, and CI wiring guards.
- Modify `nix/home/common.nix`: persistent Homebrew PATH entries.
- Modify `docker/hermes-agent/compose.yml`: explicit amd64 Chromium platform on Apple Silicon.
- Modify `README.md`: OS-specific quick start and Docker Desktop notice.
- Modify `.github/workflows/ci-devcontainer.yml`: run shell tests when installer files change.

### Task 1: Add the macOS dispatcher

**Files:**
- Create: `tests/bash/install_dispatcher.bats`
- Create: `install.sh`

**Interfaces:**
- Consumes: `uname -s`, `uname -m`, repository-relative `scripts/sh/install-macos.sh`.
- Produces: executable `./install.sh` that `exec`s the macOS installer only on Darwin arm64.

- [ ] **Step 1: Write the failing dispatcher tests**

```bash
#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	TEST_BIN="$BATS_TEST_TMPDIR/bin"
	DISPATCH_LOG="$BATS_TEST_TMPDIR/dispatch.log"
	mkdir -p "$TEST_BIN"
	export PATH="$TEST_BIN:/usr/bin:/bin"
	export DISPATCH_LOG
}

write_uname_stub() {
	cat >"$TEST_BIN/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
	-s) printf '%s\n' "${TEST_UNAME_S}" ;;
	-m) printf '%s\n' "${TEST_UNAME_M}" ;;
	*) exit 2 ;;
esac
EOF
	chmod +x "$TEST_BIN/uname"
}

write_macos_installer_stub() {
	mkdir -p "$BATS_TEST_TMPDIR/repo/scripts/sh"
	cp "$REPO_ROOT/install.sh" "$BATS_TEST_TMPDIR/repo/install.sh"
	cat >"$BATS_TEST_TMPDIR/repo/scripts/sh/install-macos.sh" <<'EOF'
#!/usr/bin/env bash
printf 'args=%s\n' "$*" >"$DISPATCH_LOG"
EOF
	chmod +x "$BATS_TEST_TMPDIR/repo/scripts/sh/install-macos.sh"
}

@test "Darwin arm64 dispatches to the macOS installer with arguments intact" {
	write_uname_stub
	write_macos_installer_stub
	export TEST_UNAME_S=Darwin TEST_UNAME_M=arm64

	run "$BATS_TEST_TMPDIR/repo/install.sh" --example

	[ "$status" -eq 0 ]
	grep -q '^args=--example$' "$DISPATCH_LOG"
}

@test "Windows-like environments direct the user to install.cmd" {
	write_uname_stub
	export TEST_UNAME_S=MINGW64_NT TEST_UNAME_M=x86_64

	run "$REPO_ROOT/install.sh"

	[ "$status" -ne 0 ]
	[[ "$output" == *"install.cmd"* ]]
}

@test "Intel macOS is rejected explicitly" {
	write_uname_stub
	export TEST_UNAME_S=Darwin TEST_UNAME_M=x86_64

	run "$REPO_ROOT/install.sh"

	[ "$status" -ne 0 ]
	[[ "$output" == *"Apple Silicon"* ]]
}
```

- [ ] **Step 2: Run the dispatcher tests and verify RED**

Run:

```bash
bats tests/bash/install_dispatcher.bats
```

Expected: FAIL because `install.sh` does not exist.

- [ ] **Step 3: Implement the minimal dispatcher**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
os="$(uname -s)"
arch="$(uname -m)"

if [[ "$os" == "Darwin" && "$arch" == "arm64" ]]; then
	exec "$ROOT/scripts/sh/install-macos.sh" "$@"
fi

if [[ "$os" == MINGW* || "$os" == MSYS* || "$os" == CYGWIN* ]]; then
	printf 'Windows setup uses install.cmd.\n' >&2
	exit 1
fi

if [[ "$os" == "Darwin" ]]; then
	printf 'This installer supports Apple Silicon Macs only (detected %s).\n' "$arch" >&2
	exit 1
fi

printf 'This installer supports Apple Silicon macOS only. Use the existing NixOS/Linux instructions on %s.\n' "$os" >&2
exit 1
```

Make it executable:

```bash
chmod +x install.sh
```

- [ ] **Step 4: Run the dispatcher tests and verify GREEN**

Run:

```bash
bats tests/bash/install_dispatcher.bats
```

Expected: 3 tests pass.

- [ ] **Step 5: Commit the dispatcher**

```bash
git add install.sh tests/bash/install_dispatcher.bats
git commit -m "feat: add macOS installer entrypoint"
```

### Task 2: Implement the idempotent macOS provisioning workflow

**Files:**
- Create: `tests/bash/install_macos.bats`
- Create: `scripts/sh/install-macos.sh`

**Interfaces:**
- Consumes: the repository checkout, standard macOS utilities, Homebrew, Docker Desktop CLI, Nix, Home Manager activation package, chezmoi, and Docker Compose.
- Produces: `main`, phase functions, and a complete provisioning run.
- Supported test overrides:
  - `DOTFILES_BREW_BIN`
  - `DOTFILES_DOCKER_APP_PATH`
  - `DOTFILES_DOCKER_SETUP_MARKER`
  - `DOTFILES_NIX_PROFILE_SCRIPT`
  - `DOTFILES_DOCKER_WAIT_ATTEMPTS`
  - `DOTFILES_SERVICE_WAIT_ATTEMPTS`
  - `DOTFILES_WAIT_SLEEP_SECONDS`

- [ ] **Step 1: Write the installed-state end-to-end failing test**

Create `tests/bash/install_macos.bats` with the following fixture and first test:

```bash
#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	INSTALLER="$REPO_ROOT/scripts/sh/install-macos.sh"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	FAKE_DOCKER_APP="$BATS_TEST_TMPDIR/Docker.app"
	FAKE_NIX_PROFILE="$BATS_TEST_TMPDIR/nix-daemon.sh"
	ACTIVATION="$BATS_TEST_TMPDIR/home-manager-generation"
	mkdir -p "$TEST_HOME" "$STUB_BIN" "$ACTIVATION"
	: >"$COMMAND_LOG"
	: >"$FAKE_NIX_PROFILE"

	export HOME="$TEST_HOME"
	export USER="test-user"
	export PATH="$STUB_BIN:/usr/bin:/bin"
	export COMMAND_LOG STUB_BIN ACTIVATION
	export DOTFILES_BREW_BIN="$STUB_BIN/brew"
	export DOTFILES_DOCKER_APP_PATH="$FAKE_DOCKER_APP"
	export DOTFILES_DOCKER_SETUP_MARKER="$TEST_HOME/.config/dotfiles/docker-desktop-installed"
	export DOTFILES_NIX_PROFILE_SCRIPT="$FAKE_NIX_PROFILE"
	export DOTFILES_DOCKER_WAIT_ATTEMPTS=2
	export DOTFILES_SERVICE_WAIT_ATTEMPTS=2
	export DOTFILES_WAIT_SLEEP_SECONDS=0

	cat >"$ACTIVATION/activate" <<'EOF'
#!/usr/bin/env bash
printf 'activate\n' >>"$COMMAND_LOG"
mkdir -p "$HOME/.nix-profile/bin"
if [ -n "${ACTIVATE_INSTALL_CHEZMOI:-}" ]; then
	cat >"$HOME/.nix-profile/bin/chezmoi" <<'STUB'
#!/usr/bin/env bash
printf 'chezmoi %s\n' "$*" >>"$COMMAND_LOG"
STUB
	chmod +x "$HOME/.nix-profile/bin/chezmoi"
fi
EOF
	chmod +x "$ACTIVATION/activate"

	write_stub uname '
case "${1:-}" in
	-s) echo Darwin ;;
	-m) echo arm64 ;;
	*) exit 2 ;;
esac
'
	write_stub sw_vers '
[ "${1:-}" = "-productVersion" ] && echo 26.5.1
'
	write_stub xcode-select '
[ "${1:-}" = "-p" ] && { echo /Library/Developer/CommandLineTools; exit 0; }
exit 2
'
	write_stub nc 'exit 0'
	write_stub sleep 'exit 0'
	write_stub date 'echo 20260717010203'
	write_stub sudo '
printf "sudo %s\n" "$*" >>"$COMMAND_LOG"
exec "$@"
'
}

write_stub() {
	local name="$1"
	local body="$2"
	cat >"$STUB_BIN/$name" <<EOF
#!/usr/bin/env bash
set -euo pipefail
$body
EOF
	chmod +x "$STUB_BIN/$name"
}

write_installed_stubs() {
	mkdir -p "$FAKE_DOCKER_APP/Contents/MacOS" "$FAKE_DOCKER_APP/Contents/Resources/bin"
	cat >"$FAKE_DOCKER_APP/Contents/MacOS/install" <<'EOF'
#!/usr/bin/env bash
printf 'docker-install %s\n' "$*" >>"$COMMAND_LOG"
EOF
	chmod +x "$FAKE_DOCKER_APP/Contents/MacOS/install"
	mkdir -p "$(dirname "$DOTFILES_DOCKER_SETUP_MARKER")"
	touch "$DOTFILES_DOCKER_SETUP_MARKER"

	write_stub pkgutil 'exit 0'
	write_stub softwareupdate 'printf "softwareupdate %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub brew '
printf "brew %s\n" "$*" >>"$COMMAND_LOG"
if [ "${1:-}" = "shellenv" ]; then
	printf "export PATH=%q:\$PATH\n" "$STUB_BIN"
fi
'
	write_stub nix '
printf "nix %s\n" "$*" >>"$COMMAND_LOG"
if [ "${1:-}" = "build" ]; then
	printf "%s\n" "$ACTIVATION"
fi
'
	write_stub chezmoi 'printf "chezmoi %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub docker '
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
exit 0
'
	ln -s "$REPO_ROOT" "$HOME/.dotfiles"
}

assert_log_order() {
	local previous=0 pattern line
	for pattern in "$@"; do
		line="$(grep -nF "$pattern" "$COMMAND_LOG" | head -1 | cut -d: -f1)"
		[ -n "$line" ]
		[ "$line" -gt "$previous" ]
		previous="$line"
	done
}

@test "installed prerequisites run Home Manager, chezmoi, and Compose in order without reinstalling" {
	write_installed_stubs

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	assert_log_order \
		"nix build --no-link --print-out-paths .#homeConfigurations.aarch64-darwin.activationPackage --impure" \
		"activate" \
		"chezmoi init --source $REPO_ROOT/chezmoi" \
		"chezmoi apply --force" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml config" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml build --pull" \
		"docker compose -f $REPO_ROOT/docker/hermes-agent/compose.yml up -d --force-recreate --wait"
	! grep -q 'brew install' "$COMMAND_LOG"
	! grep -q 'softwareupdate' "$COMMAND_LOG"
	! grep -q 'docker-install' "$COMMAND_LOG"
}
```

- [ ] **Step 2: Run the installed-state test and verify RED**

Run:

```bash
bats tests/bash/install_macos.bats
```

Expected: FAIL because `scripts/sh/install-macos.sh` does not exist.

- [ ] **Step 3: Implement shared logging, validation, and bounded polling**

The script starts with:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="$ROOT/docker/hermes-agent/compose.yml"
BREW_BIN="${DOTFILES_BREW_BIN:-/opt/homebrew/bin/brew}"
DOCKER_APP="${DOTFILES_DOCKER_APP_PATH:-/Applications/Docker.app}"
DOCKER_SETUP_MARKER="${DOTFILES_DOCKER_SETUP_MARKER:-$HOME/.config/dotfiles/docker-desktop-installed}"
NIX_PROFILE_SCRIPT="${DOTFILES_NIX_PROFILE_SCRIPT:-/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh}"
DOCKER_WAIT_ATTEMPTS="${DOTFILES_DOCKER_WAIT_ATTEMPTS:-120}"
SERVICE_WAIT_ATTEMPTS="${DOTFILES_SERVICE_WAIT_ATTEMPTS:-60}"
WAIT_SLEEP_SECONDS="${DOTFILES_WAIT_SLEEP_SECONDS:-2}"

log() { printf '\033[1;34m[macos-install]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[macos-install]\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

wait_for() {
	local attempts="$1" label="$2"
	shift 2
	local attempt
	for ((attempt = 1; attempt <= attempts; attempt++)); do
		if "$@" >/dev/null 2>&1; then
			return 0
		fi
		if ((attempt < attempts)); then
			sleep "$WAIT_SLEEP_SECONDS"
		fi
	done
	die "Timed out waiting for $label after $attempts attempts."
}
```

Add:

```bash
preflight() {
	local os arch version major required
	os="$(uname -s)"
	arch="$(uname -m)"
	[[ "$os" == "Darwin" ]] || die "macOS is required (detected $os)."
	[[ "$arch" == "arm64" ]] || die "Apple Silicon is required (detected $arch)."

	version="$(sw_vers -productVersion)"
	major="${version%%.*}"
	[[ "$major" =~ ^[0-9]+$ ]] || die "Unable to parse macOS version: $version"
	((major >= 26)) || die "macOS 26 or later is required (detected $version)."

	if ! xcode-select -p >/dev/null 2>&1; then
		xcode-select --install || true
		die "Command Line Tools installation was requested. Complete it, then rerun ./install.sh."
	fi

	for required in \
		"$ROOT/flake.nix" \
		"$ROOT/chezmoi" \
		"$COMPOSE_FILE"; do
		[[ -e "$required" ]] || die "Required repository path is missing: $required"
	done
}
```

- [ ] **Step 4: Implement Homebrew, Rosetta, and Docker Desktop phases**

Use:

```bash
ensure_homebrew() {
	if ! have brew; then
		log "Installing Homebrew..."
		NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	fi
	if have brew; then
		eval "$(brew shellenv)"
	elif [[ -x "$BREW_BIN" ]]; then
		eval "$("$BREW_BIN" shellenv)"
	else
		die "Homebrew installation completed but brew is unavailable."
	fi
}

ensure_rosetta() {
	if ! pkgutil --pkg-info com.apple.pkg.RosettaUpdateAuto >/dev/null 2>&1; then
		log "Installing Rosetta 2 for linux/amd64 containers..."
		softwareupdate --install-rosetta --agree-to-license
	fi
}

ensure_docker_desktop() {
	if [[ ! -d "$DOCKER_APP" ]]; then
		log "Installing Docker Desktop..."
		brew install --cask docker-desktop
	fi
	local installer="$DOCKER_APP/Contents/MacOS/install"
	[[ -x "$installer" ]] || die "Docker Desktop installer not found: $installer"
	if [[ ! -f "$DOCKER_SETUP_MARKER" ]]; then
		log "Accepting the Docker Desktop license and applying user configuration..."
		sudo "$installer" --accept-license --user="$USER"
		mkdir -p "$(dirname "$DOCKER_SETUP_MARKER")"
		touch "$DOCKER_SETUP_MARKER"
	fi
	ensure_rosetta
	export PATH="$DOCKER_APP/Contents/Resources/bin:$PATH"
	docker desktop start --timeout 120
	wait_for "$DOCKER_WAIT_ATTEMPTS" "Docker Desktop engine" docker info
	docker compose version >/dev/null
}
```

- [ ] **Step 5: Implement Nix, repository link, Home Manager, and chezmoi phases**

Use:

```bash
load_nix_profile() {
	if [[ -r "$NIX_PROFILE_SCRIPT" ]]; then
		# shellcheck source=/dev/null
		. "$NIX_PROFILE_SCRIPT"
	fi
}

ensure_nix() {
	load_nix_profile
	if ! have nix; then
		log "Installing Nix in multi-user daemon mode..."
		curl -fsSL https://nixos.org/nix/install | sh -s -- --daemon
		load_nix_profile
	fi
	have nix || die "Nix installation completed but nix is unavailable."
	mkdir -p "$HOME/.config/nix"
	local feature_line="extra-experimental-features = nix-command flakes"
	touch "$HOME/.config/nix/nix.conf"
	grep -Fxq "$feature_line" "$HOME/.config/nix/nix.conf" ||
		printf '%s\n' "$feature_line" >>"$HOME/.config/nix/nix.conf"
}

link_dotfiles() {
	local target="$HOME/.dotfiles"
	if [[ -L "$target" && "$(cd "$(dirname "$target")" && pwd -P)/$(readlink "$target")" == "$ROOT" ]]; then
		return
	fi
	if [[ -e "$target" || -L "$target" ]]; then
		local backup="$HOME/.dotfiles.backup.$(date +%Y%m%d%H%M%S)"
		mv "$target" "$backup"
		log "Moved existing $target to $backup"
	fi
	ln -s "$ROOT" "$target"
}

activate_home_manager() {
	log "Building Home Manager configuration..."
	local activation
	activation="$(cd "$ROOT" && nix build --no-link --print-out-paths \
		.#homeConfigurations.aarch64-darwin.activationPackage --impure)"
	[[ -x "$activation/activate" ]] || die "Home Manager activation script not found: $activation/activate"
	"$activation/activate"
	export PATH="$HOME/.nix-profile/bin:$HOME/.local/state/nix/profile/bin:$PATH"
}

apply_chezmoi() {
	have chezmoi || die "chezmoi is unavailable after Home Manager activation."
	chezmoi init --source "$ROOT/chezmoi"
	chezmoi apply --force
}
```

Resolve the symlink comparison with `realpath` when available and a `cd -P` fallback so relative links are handled correctly.

- [ ] **Step 6: Implement Compose build, startup, diagnostics, and orchestration**

Use:

```bash
show_compose_diagnostics() {
	docker compose -f "$COMPOSE_FILE" ps || true
	docker compose -f "$COMPOSE_FILE" logs --tail=100 || true
}

start_hermes_stack() {
	log "Validating Hermes Docker Compose configuration..."
	docker compose -f "$COMPOSE_FILE" config
	log "Building Hermes images..."
	docker compose -f "$COMPOSE_FILE" build --pull
	log "Starting Hermes services..."
	if ! docker compose -f "$COMPOSE_FILE" up -d --force-recreate --wait; then
		show_compose_diagnostics
		die "Hermes Docker Compose startup failed."
	fi
	docker compose -f "$COMPOSE_FILE" ps
	wait_for "$SERVICE_WAIT_ATTEMPTS" "Hermes API port" nc -z 127.0.0.1 "${HERMES_API_PORT:-8642}"
	wait_for "$SERVICE_WAIT_ATTEMPTS" "Hermes dashboard port" nc -z 127.0.0.1 "${HERMES_DASHBOARD_PORT:-9119}"
	wait_for "$SERVICE_WAIT_ATTEMPTS" "Hermes browser viewer port" nc -z 127.0.0.1 "${HERMES_BROWSER_VIEW_PORT:-6080}"
}

main() {
	preflight
	log "Docker Desktop is subject to Docker's license terms; continuing for personal use."
	ensure_homebrew
	ensure_docker_desktop
	ensure_nix
	link_dotfiles
	activate_home_manager
	apply_chezmoi
	start_hermes_stack
	log "macOS setup complete."
}

main "$@"
```

Make it executable:

```bash
chmod +x scripts/sh/install-macos.sh
```

- [ ] **Step 7: Verify the installed-state test is GREEN**

Run:

```bash
bats tests/bash/install_macos.bats
```

Expected: installed-state orchestration test passes.

- [ ] **Step 8: Add RED tests for fresh install, backup, and timeout**

Add these helpers and tests to the same file:

```bash
write_fresh_install_stubs() {
	write_stub pkgutil 'exit 1'
	write_stub softwareupdate 'printf "softwareupdate %s\n" "$*" >>"$COMMAND_LOG"'
	write_stub curl '
case "$*" in
	*raw.githubusercontent.com/Homebrew/install*)
		cat <<'"'"'SCRIPT'"'"'
mkdir -p "$(dirname "$DOTFILES_BREW_BIN")"
cat >"$DOTFILES_BREW_BIN" <<'"'"'BREW'"'"'
#!/usr/bin/env bash
set -euo pipefail
printf "brew %s\n" "$*" >>"$COMMAND_LOG"
case "${1:-}" in
	shellenv)
		printf "export PATH=%q:\$PATH\n" "$(dirname "$DOTFILES_BREW_BIN")"
		;;
	install)
		mkdir -p "$DOTFILES_DOCKER_APP_PATH/Contents/MacOS" "$DOTFILES_DOCKER_APP_PATH/Contents/Resources/bin"
		cat >"$DOTFILES_DOCKER_APP_PATH/Contents/MacOS/install" <<'"'"'DOCKER_INSTALL'"'"'
#!/usr/bin/env bash
printf "docker-install %s\n" "$*" >>"$COMMAND_LOG"
DOCKER_INSTALL
		chmod +x "$DOTFILES_DOCKER_APP_PATH/Contents/MacOS/install"
		cat >"$DOTFILES_DOCKER_APP_PATH/Contents/Resources/bin/docker" <<'"'"'DOCKER'"'"'
#!/usr/bin/env bash
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
exit 0
DOCKER
		chmod +x "$DOTFILES_DOCKER_APP_PATH/Contents/Resources/bin/docker"
		;;
esac
BREW
chmod +x "$DOTFILES_BREW_BIN"
SCRIPT
		;;
	*nixos.org/nix/install*)
		cat <<'"'"'SCRIPT'"'"'
printf "nix-installer %s\n" "$*" >>"$COMMAND_LOG"
cat >"$STUB_BIN/nix" <<'"'"'NIX'"'"'
#!/usr/bin/env bash
printf "nix %s\n" "$*" >>"$COMMAND_LOG"
if [ "${1:-}" = "build" ]; then
	printf "%s\n" "$ACTIVATION"
fi
NIX
chmod +x "$STUB_BIN/nix"
SCRIPT
		;;
	*) exit 2 ;;
esac
'
	export ACTIVATE_INSTALL_CHEZMOI=1
}

@test "fresh install provisions Homebrew Docker Desktop Rosetta and Nix with required arguments" {
	write_fresh_install_stubs

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	grep -q 'brew install --cask docker-desktop' "$COMMAND_LOG"
	grep -q 'sudo .* --accept-license --user=test-user' "$COMMAND_LOG"
	grep -q 'docker-install --accept-license --user=test-user' "$COMMAND_LOG"
	grep -q 'softwareupdate --install-rosetta --agree-to-license' "$COMMAND_LOG"
	grep -q 'nix-installer --daemon' "$COMMAND_LOG"
}

@test "an existing dotfiles directory is moved to a timestamped backup" {
	write_installed_stubs
	rm "$HOME/.dotfiles"
	mkdir -p "$HOME/.dotfiles"
	echo keep >"$HOME/.dotfiles/existing.txt"

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	[ -L "$HOME/.dotfiles" ]
	[ -f "$HOME/.dotfiles.backup.20260717010203/existing.txt" ]
	[ "$(find "$HOME" -maxdepth 1 -name '.dotfiles.backup.*' | wc -l | tr -d ' ')" -eq 1 ]
}

@test "Docker engine readiness timeout fails after the configured attempt count" {
	write_installed_stubs
	write_stub docker '
printf "docker %s\n" "$*" >>"$COMMAND_LOG"
if [ "${1:-}" = "info" ]; then exit 1; fi
exit 0
'

	run "$INSTALLER"

	[ "$status" -ne 0 ]
	[[ "$output" == *"Timed out waiting for Docker Desktop engine after 2 attempts."* ]]
	[ "$(grep -c '^docker info$' "$COMMAND_LOG")" -eq 2 ]
}
```

- [ ] **Step 9: Run the new tests and verify RED for missing edge handling**

Run:

```bash
bats tests/bash/install_macos.bats
```

Expected: at least one new test fails because fresh-install command creation, backup resolution, or bounded timeout behavior is incomplete.

- [ ] **Step 10: Implement the minimal fixes and verify GREEN**

Use these exact corrections if the tests expose the corresponding issue:

```bash
canonical_path() {
	local path="$1"
	if have realpath; then
		realpath "$path"
		return
	fi
	(
		cd "$(dirname "$path")"
		printf '%s/%s\n' "$(pwd -P)" "$(basename "$path")"
	)
}

link_dotfiles() {
	local target="$HOME/.dotfiles"
	if [[ -L "$target" && "$(canonical_path "$target")" == "$ROOT" ]]; then
		return
	fi
	if [[ -e "$target" || -L "$target" ]]; then
		local backup="$HOME/.dotfiles.backup.$(date +%Y%m%d%H%M%S)"
		mv "$target" "$backup"
		log "Moved existing $target to $backup"
	fi
	ln -s "$ROOT" "$target"
}
```

Keep Docker calls resolved through the PATH updated with
`$DOCKER_APP/Contents/Resources/bin`, then run:

```bash
bats tests/bash/install_macos.bats
```

Expected: all installer tests pass.

- [ ] **Step 11: Commit the provisioning workflow**

```bash
git add scripts/sh/install-macos.sh tests/bash/install_macos.bats
git commit -m "feat: provision macOS development environment"
```

### Task 3: Wire macOS paths and Docker architecture

**Files:**
- Create: `tests/bash/macos_config.bats`
- Modify: `nix/home/common.nix`
- Modify: `docker/hermes-agent/compose.yml`

**Interfaces:**
- Consumes: Home Manager session configuration and the existing Compose services.
- Produces: persistent Homebrew PATH and deterministic amd64 Chromium builds on Apple Silicon.

- [ ] **Step 1: Write failing static guards**

```bash
#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "Home Manager exposes Apple Silicon Homebrew paths" {
	run awk '
		/lib\.optionals pkgs\.stdenv\.isDarwin/ { in_darwin=1 }
		in_darwin && /"\/opt\/homebrew\/bin"/ { bin=1 }
		in_darwin && /"\/opt\/homebrew\/sbin"/ { sbin=1 }
		in_darwin && /\];/ { exit(bin && sbin ? 0 : 1) }
		END { if (!in_darwin) exit 1 }
	' "$REPO_ROOT/nix/home/common.nix"
	[ "$status" -eq 0 ]
}

@test "Chromium Compose service is pinned to linux amd64" {
	run awk '
		/^  chromium:/ { in_chromium=1; next }
		in_chromium && /^  [A-Za-z0-9_-]+:/ { exit }
		in_chromium && /platform: linux\/amd64/ { found=1 }
		END { exit(found ? 0 : 1) }
	' "$REPO_ROOT/docker/hermes-agent/compose.yml"
	[ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run the static guards and verify RED**

Run:

```bash
bats tests/bash/macos_config.bats
```

Expected: 2 tests fail.

- [ ] **Step 3: Add Homebrew session paths**

In `nix/home/common.nix`, extend `home.sessionPath`:

```nix
  home.sessionPath = [
    "$HOME/.bun/bin"
    "$HOME/.local/share/pnpm/bin"
    "$HOME/.local/share/pnpm"
  ]
  ++ lib.optionals pkgs.stdenv.isDarwin [
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
  ];
```

- [ ] **Step 4: Pin Chromium to amd64**

In `docker/hermes-agent/compose.yml`:

```yaml
  chromium:
    platform: linux/amd64
    build:
      context: ../hermes-browser
      dockerfile: Dockerfile
```

- [ ] **Step 5: Run guards and repository config checks**

Run:

```bash
bats tests/bash/macos_config.bats
docker compose -f docker/hermes-agent/compose.yml config
```

Expected: tests pass and Compose config exits 0.

- [ ] **Step 6: Commit platform wiring**

```bash
git add nix/home/common.nix docker/hermes-agent/compose.yml tests/bash/macos_config.bats
git commit -m "feat: configure macOS package and container paths"
```

### Task 4: Document and enable CI coverage

**Files:**
- Modify: `README.md`
- Modify: `.github/workflows/ci-devcontainer.yml`
- Modify: `tests/bash/macos_config.bats`

**Interfaces:**
- Consumes: the new installer commands.
- Produces: user-facing quick start and CI triggers for installer regressions.

- [ ] **Step 1: Add failing documentation and CI guards**

Append tests:

```bash
@test "README documents the one-command macOS installer" {
	run grep -F './install.sh' "$REPO_ROOT/README.md"
	[ "$status" -eq 0 ]
	run grep -F 'Docker Desktop' "$REPO_ROOT/README.md"
	[ "$status" -eq 0 ]
}

@test "devcontainer CI watches macOS installer files" {
	run grep -F '"install.sh"' "$REPO_ROOT/.github/workflows/ci-devcontainer.yml"
	[ "$status" -eq 0 ]
	run grep -F '"scripts/sh/install-macos.sh"' "$REPO_ROOT/.github/workflows/ci-devcontainer.yml"
	[ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run guards and verify RED**

Run:

```bash
bats tests/bash/macos_config.bats
```

Expected: README and CI guard tests fail.

- [ ] **Step 3: Update README quick start**

Split the quick start into:

````markdown
### macOS (Apple Silicon)

Requirements: macOS 26 or later and an administrator account. The installer uses
Docker Desktop under its license terms and may prompt for administrator approval.

```bash
git clone https://github.com/rurusasu/dotfiles.git
cd dotfiles
./install.sh
```

The command installs Homebrew, Docker Desktop, Nix, Home Manager packages,
chezmoi configuration, and starts the Hermes Docker Compose stack. It is safe to
rerun after a partial failure. The first image build can take a while.

### Windows
````

Keep the existing Windows commands and NixOS/WSL explanation after the Windows heading.

- [ ] **Step 4: Update CI path triggers**

Add these paths to both `push.paths` and `pull_request.paths`:

```yaml
      - "install.sh"
      - "scripts/sh/install-macos.sh"
```

The existing `tests/bash/**` trigger ensures the new Bats files are covered.

- [ ] **Step 5: Run guards and verify GREEN**

Run:

```bash
bats tests/bash/macos_config.bats
```

Expected: all config/documentation guards pass.

- [ ] **Step 6: Commit documentation and CI**

```bash
git add README.md .github/workflows/ci-devcontainer.yml tests/bash/macos_config.bats
git commit -m "docs: add macOS bootstrap quick start"
```

### Task 5: Full verification and real macOS installation

**Files:**
- Verify all modified files.
- Runtime state changes occur under `/Applications`, `/opt/homebrew`, `/nix`, the user's home directory, and Docker Desktop.

**Interfaces:**
- Consumes: completed implementation and the user's Apple Silicon Mac.
- Produces: verified source changes and a configured local machine.

- [ ] **Step 1: Run source-level verification**

Run:

```bash
bash -n install.sh scripts/sh/install-macos.sh
bats tests/bash
git diff --check
```

Expected: syntax clean, all Bats tests pass, no whitespace errors.

- [ ] **Step 2: Run Nix and Compose evaluation where dependencies are available**

Run:

```bash
nix flake check --no-build
docker compose -f docker/hermes-agent/compose.yml config
```

Expected: both exit 0 with no evaluation warning.

- [ ] **Step 3: Review the diff before host mutation**

Run:

```bash
git status --short --branch
git diff origin/main...HEAD --stat
git diff origin/main...HEAD -- install.sh scripts/sh/install-macos.sh nix/home/common.nix docker/hermes-agent/compose.yml README.md .github/workflows/ci-devcontainer.yml tests/bash
```

Expected: only planned files and the already-approved design/plan documents differ.

- [ ] **Step 4: Execute the real installer**

Run in a PTY:

```bash
./install.sh
```

Expected:

- Homebrew installs if absent.
- Docker Desktop installs, accepts its license for the current personal-use user, starts, and becomes ready.
- Rosetta installs if absent.
- Nix installs in daemon mode if absent.
- Home Manager activation completes.
- chezmoi applies.
- Hermes images build and Compose services start.

Do not request or transmit the user's administrator password in chat. If macOS presents a native authorization prompt, pause and ask the user to approve it locally.

- [ ] **Step 5: Verify installed tools**

Run:

```bash
brew --version
nix --version
home-manager --version
chezmoi --version
docker version
docker compose version
gh --version
nvim --version
```

Expected: every command exits 0.

- [ ] **Step 6: Verify the Hermes runtime**

Run:

```bash
docker compose -f docker/hermes-agent/compose.yml ps
docker inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' hermes
docker inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' hermes-chromium
docker inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' hermes-browser-mcp
nc -z 127.0.0.1 "${HERMES_API_PORT:-8642}"
nc -z 127.0.0.1 "${HERMES_DASHBOARD_PORT:-9119}"
nc -z 127.0.0.1 "${HERMES_BROWSER_VIEW_PORT:-6080}"
```

Expected: Hermes is running; Chromium and Browser MCP are healthy; all three ports accept connections.

- [ ] **Step 7: Re-run the installer to verify idempotency**

Run:

```bash
./install.sh
```

Expected: no Homebrew, Docker Desktop, Rosetta, or Nix reinstall; Home Manager, chezmoi, and Compose converge successfully; no additional dotfiles backup is created.

- [ ] **Step 8: Run final verification before completion**

Run:

```bash
bash -n install.sh scripts/sh/install-macos.sh
bats tests/bash
nix flake check --no-build
docker compose -f docker/hermes-agent/compose.yml config
git diff --check
git status --short --branch
```

Expected: all checks pass and the worktree contains only intentional commits/changes.
