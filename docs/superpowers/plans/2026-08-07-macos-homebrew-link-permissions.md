# macOS Homebrew Cask Link Permission Convergence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Converge Docker Desktop's `/usr/local` cask link directories before cask upgrades so `nrs` can update Docker Desktop without a permission rollback.

**Architecture:** `install-macos.sh` owns the boundary between successful `nix-darwin` activation and the cask updater. Add one defensive directory helper and a two-directory wrapper at that boundary; reject unsafe targets, then use narrow non-recursive `sudo` operations to set the configured macOS user, `admin` group, and mode `0775`.

**Tech Stack:** Bash 5, Bats, macOS BSD utilities, Homebrew, nix-darwin, nix-homebrew, Task, pre-commit

## Global Constraints

- Only `/usr/local/bin` and `/usr/local/cli-plugins`, or their test-injected replacements, may be changed.
- Ownership and permission changes must be non-recursive.
- Symbolic-link and non-directory targets must fail before privileged mutation or cask update.
- Production owner/group must be `$DOTFILES_USER:admin`; production mode must be exactly `0775`.
- Directory convergence must run after `apply_darwin_system` and before `HOMEBREW_CASK_UPDATER`.
- Existing cask updater retry and convergence behavior must remain unchanged.

### Final implementation decision

This decision supersedes Task 1's injectable production-path and sequential helper examples. The production wrapper passes only literal `/usr/local/bin` and `/usr/local/cli-plugins`. Before any mutation it validates both targets and the immutable parent invariant: `/usr/local` must be a real root-owned directory with no group/other write bits. The parent and current target are revalidated immediately before each target sequence, and missing final components use non-`-p` `mkdir --`.

Test isolation uses the installer's source guard and under-parent function boundary rather than production environment overrides. Both Bats sudo fixtures use complete scenario-specific exact-argv allowlists, delimited per-argument logs, status 97 for unknown vectors, exact total-count assertions, and injected `mkdir`/`chown`/`chmod` failures.

---

### Task 1: Converge Homebrew cask link directories

**Files:**

- Modify: `tests/bash/install_macos.bats`
- Modify: `scripts/sh/install-macos.sh`

**Interfaces:**

- Consumes: `DOTFILES_USER`, set by `apply_darwin_system`; `dotfiles_die` and `dotfiles_log` from `scripts/sh/install-common.sh`; `sudo` authorization already established by `nix-darwin` activation.
- Produces: `ensure_homebrew_cask_link_directory(path)` and `ensure_homebrew_cask_link_directories()`; environment overrides `DOTFILES_HOMEBREW_CASK_BIN_DIR` and `DOTFILES_HOMEBREW_CASK_CLI_PLUGIN_DIR`.

- [ ] **Step 1: Add test isolation for privileged directory operations**

In `setup()` in `tests/bash/install_macos.bats`, add temporary targets beside the other `DOTFILES_*` overrides:

```bash
export DOTFILES_HOMEBREW_CASK_BIN_DIR="$BATS_TEST_TMPDIR/usr/local/bin"
export DOTFILES_HOMEBREW_CASK_CLI_PLUGIN_DIR="$BATS_TEST_TMPDIR/usr/local/cli-plugins"
```

Replace the existing `sudo` stub body with this behavior. It records every invocation, treats the three narrowly scoped privileged filesystem operations as successful external boundaries, and continues to execute `nix` and the existing Docker installer stubs:

```bash
write_stub sudo '
printf "sudo %s\n" "$*" >>"$COMMAND_LOG"
case "${1:-}" in
	/bin/mkdir | /usr/sbin/chown | /bin/chmod) exit 0 ;;
esac
exec "$@"
'
```

- [ ] **Step 2: Write failing behavior tests**

Add these tests after `installed prerequisites run nix-darwin chezmoi and Compose in order`:

```bash
@test "Homebrew cask link directories converge before cask updates" {
	write_installed_stubs

	run "$INSTALLER"

	[ "$status" -eq 0 ]
	assert_log_order \
		"nix run .#darwin-rebuild -- switch --flake .#macos --impure" \
		"sudo /bin/mkdir -p -- $DOTFILES_HOMEBREW_CASK_BIN_DIR" \
		"sudo /usr/sbin/chown test-user:admin $DOTFILES_HOMEBREW_CASK_BIN_DIR" \
		"sudo /bin/chmod 0775 $DOTFILES_HOMEBREW_CASK_BIN_DIR" \
		"sudo /bin/mkdir -p -- $DOTFILES_HOMEBREW_CASK_CLI_PLUGIN_DIR" \
		"sudo /usr/sbin/chown test-user:admin $DOTFILES_HOMEBREW_CASK_CLI_PLUGIN_DIR" \
		"sudo /bin/chmod 0775 $DOTFILES_HOMEBREW_CASK_CLI_PLUGIN_DIR" \
		"update-homebrew-casks "
}

@test "symbolic Homebrew cask link directory stops before mutation" {
	write_installed_stubs
	mkdir -p "$(dirname "$DOTFILES_HOMEBREW_CASK_BIN_DIR")" "$BATS_TEST_TMPDIR/link-target"
	ln -s "$BATS_TEST_TMPDIR/link-target" "$DOTFILES_HOMEBREW_CASK_BIN_DIR"

	run "$INSTALLER"

	[ "$status" -ne 0 ]
	[[ "$output" == *"Refusing symbolic Homebrew cask link directory: $DOTFILES_HOMEBREW_CASK_BIN_DIR"* ]]
	! grep -q '^sudo /bin/mkdir ' "$COMMAND_LOG"
	! grep -q '^update-homebrew-casks ' "$COMMAND_LOG"
}

@test "non-directory Homebrew cask link target stops before mutation" {
	write_installed_stubs
	mkdir -p "$(dirname "$DOTFILES_HOMEBREW_CASK_BIN_DIR")"
	touch "$DOTFILES_HOMEBREW_CASK_BIN_DIR"

	run "$INSTALLER"

	[ "$status" -ne 0 ]
	[[ "$output" == *"Homebrew cask link path is not a directory: $DOTFILES_HOMEBREW_CASK_BIN_DIR"* ]]
	! grep -q '^sudo /bin/mkdir ' "$COMMAND_LOG"
	! grep -q '^update-homebrew-casks ' "$COMMAND_LOG"
}
```

These tests catch a missing convergence call, wrong directory, wrong owner/group, wrong mode, incorrect ordering, or missing unsafe-target validation. Assertions use hand-derived literal commands and run the real installer; only privileged external commands are stubbed.

- [ ] **Step 3: Run the focused suite and verify RED**

Run:

```bash
bats tests/bash/install_macos.bats
```

Expected: 12 existing tests pass and the three new tests fail because the convergence commands and validation do not exist yet.

- [ ] **Step 4: Implement the minimal directory convergence**

Add the two path defaults beside the existing macOS installer constants:

```bash
HOMEBREW_CASK_BIN_DIR="${DOTFILES_HOMEBREW_CASK_BIN_DIR:-/usr/local/bin}"
HOMEBREW_CASK_CLI_PLUGIN_DIR="${DOTFILES_HOMEBREW_CASK_CLI_PLUGIN_DIR:-/usr/local/cli-plugins}"
```

Add these functions after `apply_darwin_system()` and before `setup_docker_runtime()`:

```bash
ensure_homebrew_cask_link_directory() {
  local directory="$1"

  [[ ! -L $directory ]] ||
    dotfiles_die "Refusing symbolic Homebrew cask link directory: $directory"
  [[ ! -e $directory || -d $directory ]] ||
    dotfiles_die "Homebrew cask link path is not a directory: $directory"

  sudo /bin/mkdir -p -- "$directory"
  sudo /usr/sbin/chown "$DOTFILES_USER:admin" "$directory"
  sudo /bin/chmod 0775 "$directory"
}

ensure_homebrew_cask_link_directories() {
  dotfiles_log "Converging Homebrew cask link directory permissions..."
  ensure_homebrew_cask_link_directory "$HOMEBREW_CASK_BIN_DIR"
  ensure_homebrew_cask_link_directory "$HOMEBREW_CASK_CLI_PLUGIN_DIR"
}
```

Call the wrapper at the required boundary in `main()`:

```bash
  apply_darwin_system
  ensure_homebrew_cask_link_directories
  "$HOMEBREW_CASK_UPDATER"
```

- [ ] **Step 5: Run the focused suite and verify GREEN**

Run:

```bash
bats tests/bash/install_macos.bats
```

Expected: `1..15`, all 15 tests pass.

- [ ] **Step 6: Run mutation checks**

Temporarily make each mutation separately, run the focused suite, confirm the named test fails, then restore the implementation before continuing:

1. Change `0775` to `0755`; the convergence-order test must fail.
2. Remove the call for `HOMEBREW_CASK_CLI_PLUGIN_DIR`; the convergence-order test must fail.
3. Remove the `-L` rejection; the symbolic-target test must fail.
4. Move `ensure_homebrew_cask_link_directories` below `HOMEBREW_CASK_UPDATER`; the convergence-order test must fail.

- [ ] **Step 7: Run scoped and repository validation**

Run:

```bash
bash -n scripts/sh/install-macos.sh
shellcheck scripts/sh/install-macos.sh
bats tests/bash/install_macos.bats
task test:bash DOTFILES_PATH="$PWD"
pre-commit run --all-files
git diff --check
```

Expected: syntax and ShellCheck pass; focused suite reports 15/15; full Bash suite reports 174/174; all pre-commit hooks pass; `git diff --check` emits no output.

- [ ] **Step 8: Review and commit the implementation**

Run:

```bash
git diff -- scripts/sh/install-macos.sh tests/bash/install_macos.bats
git status --short
task commit DOTFILES_PATH="$PWD" -- "fix: converge Homebrew cask link permissions"
```

Expected: the diff contains only the two planned implementation files, and the commit succeeds with all hooks passing.

---

### Task 2: Publish and merge the validated fix

**Files:**

- No new production files.
- Review: `docs/superpowers/specs/2026-08-07-macos-homebrew-link-permissions-design.md`
- Review: `docs/superpowers/plans/2026-08-07-macos-homebrew-link-permissions.md`
- Review: `scripts/sh/install-macos.sh`
- Review: `tests/bash/install_macos.bats`

**Interfaces:**

- Consumes: the clean implementation commit from Task 1 and GitHub Actions required checks.
- Produces: a merged PR on `main` with all required checks successful.

- [ ] **Step 1: Perform final branch verification**

Run:

```bash
git status --short --branch
git log --oneline --decorate main..HEAD
git diff --stat main...HEAD
task test:bash DOTFILES_PATH="$PWD"
pre-commit run --all-files
```

Expected: clean worktree; only the design, plan, installer, and installer test files differ from `main`; 174 Bash tests and all hooks pass.

- [ ] **Step 2: Push and create the PR**

Push `rurusasu/macos-homebrew-link-permissions`, then create a ready-for-review PR targeting `main`:

```text
Title: fix: converge Homebrew cask link permissions

Summary:
- repair the two /usr/local directories used by Docker Desktop cask links
- reject symlink and non-directory targets before privileged mutation
- run permission convergence after nix-darwin and before cask updates

Validation:
- bats tests/bash/install_macos.bats
- task test:bash DOTFILES_PATH="$PWD"
- pre-commit run --all-files
```

- [ ] **Step 3: Wait for Actions and merge**

Inspect every required check. If a check fails, use `github:gh-fix-ci` to distinguish code failure from runner infrastructure failure and repair or rerun as supported by evidence. Merge only when every required check is successful.

- [ ] **Step 4: Synchronize local main**

Update `/Users/ktome1995/Program/dotfiles` with a fast-forward pull and verify:

```bash
git status --short --branch
git rev-parse HEAD
git rev-parse origin/main
```

Expected: local `main` and `origin/main` identify the same merge commit and the checkout is clean.

---

### Task 3: Verify macOS runtime convergence

**Files:**

- No repository changes expected.

**Interfaces:**

- Consumes: merged `main`, macOS administrator authorization, Homebrew cask metadata, Docker Desktop runtime.
- Produces: repaired link-directory metadata, current declared casks, and a ready Docker engine.

- [ ] **Step 1: Run merged `nrs` in an external Terminal**

From `/Users/ktome1995/Program/dotfiles`, run `nrs`. Enter the macOS password only into Terminal when `sudo` prompts. Keep execution outside Orca so upgrading the Orca cask cannot terminate the installer process.

Expected log order:

```text
[macos-install] Applying nix-darwin, nix-homebrew, and Home Manager...
[macos-install] Converging Homebrew cask link directory permissions...
==> Upgrading docker-desktop
[macos-install] macOS setup complete.
```

- [ ] **Step 2: Verify directory metadata**

Run:

```bash
stat -f '%N owner=%Su group=%Sg mode=%Sp' /usr/local/bin /usr/local/cli-plugins
```

Expected: both directories report owner `ktome1995`, group `admin`, and mode `drwxrwxr-x`.

- [ ] **Step 3: Verify cask convergence**

For each declared cask (`claude`, `docker-desktop`, `google-chrome`, `stablyai/orca/orca`, `visual-studio-code`), run `brew outdated --cask --greedy <cask>` while preserving both output and exit status. Accept only status `0` with empty output as current; Homebrew status `1` plus the exact cask token means still outdated and is a failure.

Run:

```bash
brew list --cask --versions docker-desktop orca
brew info --cask docker-desktop
```

Expected: Docker Desktop is installed at 4.85.0 or the newer current cask version, Orca remains installed under token `orca`, and none of the declared casks is outdated.

- [ ] **Step 4: Verify Docker runtime**

Run:

```bash
docker info >/dev/null
docker compose version
```

Expected: both commands exit `0` and Docker Compose prints its version.
