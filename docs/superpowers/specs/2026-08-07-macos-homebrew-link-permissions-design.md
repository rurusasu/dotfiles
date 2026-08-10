# macOS Homebrew Cask Link Permission Convergence Design

## Context

`nrs` updates declared Homebrew casks after `nix-darwin` activation. Docker Desktop 4.85.0 failed during that phase while creating `/usr/local/bin/kubectl`, because `/usr/local/bin` was `root:wheel` with mode `0700`. Homebrew rolled Docker Desktop back to 4.84.0, while the other declared desktop applications upgraded successfully.

The Intel prefix was adopted by `nix-homebrew` after `/usr/local/bin` already existed. Its one-time prefix initializer checks writability while running as root, so the root-owned directory was considered writable and was not reassigned to the configured Homebrew user. The `.managed_by_nix_darwin` marker then prevented later activations from repeating that migration repair.

## Goal

Before the cask updater runs, make the two `/usr/local` directories used by Docker Desktop cask binary artifacts writable by the configured macOS Homebrew user, so upgrades converge without manual permission repair.

## Non-goals

- Do not recursively change ownership or permissions below `/usr/local`.
- Do not modify `/usr/local` itself or unrelated Homebrew directories.
- Do not change `nix-homebrew`, Homebrew, or Docker Desktop upstream code.
- Do not special-case a Docker Desktop version.
- Do not bypass the existing cask updater, retry policy, or convergence verification.

## Approaches considered

### Selected: converge link directories in `install-macos.sh`

After `apply_darwin_system` and immediately before `update-homebrew-casks.sh`, converge `/usr/local/bin` and `/usr/local/cli-plugins`. This location guarantees the repair runs after `nix-homebrew` has created or adopted the prefixes and before any cask upgrade needs the link targets. It also keeps the behavior directly testable in the existing macOS installer Bats suite.

### Rejected: nix-darwin activation script

A custom activation script could repair the directories at the system layer, but its ordering relative to `nix-homebrew` and Homebrew activation would need additional coupling to module internals. The cask updater is invoked by `install-macos.sh`, so the installer boundary is more explicit.

### Rejected: one-time manual repair

Running `chown` and `chmod` once would unblock this machine but would not protect a new or migrated installation from the same state.

## Design

`scripts/sh/install-macos.sh` will define two injectable paths with production defaults:

- `DOTFILES_HOMEBREW_CASK_BIN_DIR`, default `/usr/local/bin`
- `DOTFILES_HOMEBREW_CASK_CLI_PLUGIN_DIR`, default `/usr/local/cli-plugins`

The installer will add a focused helper that converges one directory:

1. Reject the path if it is a symbolic link.
2. Reject the path if it exists and is not a directory.
3. Create the directory with `sudo /bin/mkdir -p --` when absent.
4. Set the owner and group with `sudo /usr/sbin/chown "$DOTFILES_USER:admin"`.
5. Set the exact mode with `sudo /bin/chmod 0775`.

A wrapper will apply the helper to both configured paths. It will run after `apply_darwin_system`, which establishes `DOTFILES_USER`, and before `HOMEBREW_CASK_UPDATER`.

The operation is non-recursive and idempotent. Existing files and links inside either directory are not altered.

## Error handling and safety

- `set -euo pipefail` makes any failed create, ownership, or permission operation stop installation before a cask upgrade can enter a partial transaction.
- Symbolic-link and non-directory targets fail closed through `dotfiles_die`.
- Absolute macOS system command paths prevent shell aliases or user PATH entries from changing privileged behavior.
- `--` terminates `mkdir` options before the configured path.
- Only the two exact directory entries receive metadata changes; no recursive flags are used.
- The group is `admin`, matching the active `nix-homebrew.group` default and current configuration.

## Testing

`tests/bash/install_macos.bats` will inject temporary link-directory paths and extend the `sudo` stub for the three privileged directory operations.

Tests will prove:

1. Both directories are converged after `nix-darwin` and before the cask updater.
2. The expected owner/group and exact mode are requested for each directory.
3. A symbolic-link target is rejected before any privileged mutation or cask update.
4. Existing installer ordering and failure behavior remain intact.

The focused macOS installer suite, full Bash suite, ShellCheck, formatting hooks, and the existing macOS CI contract will be run before publishing.

## Final safety decision

This decision supersedes the injectable production paths and sequential validation example above. Production convergence is allowlisted to literal `/usr/local/bin` and `/usr/local/cli-plugins`; environment variables cannot redirect privileged mutations. Tests source the installer behind a main guard and exercise the same under-parent helper with temporary paths, while the production wrapper passes only the two literals.

Before any target mutation, the installer verifies that `/usr/local` is a real directory, is owned by root, and is not writable by group or other. It then preflights both final components before the first mutation and repeats the parent and target checks immediately before each target sequence. Because `/usr` and the validated `/usr/local` parent are immutable to the invoking user, the user cannot replace either final directory entry between validation, `chown`, and `chmod`. Missing targets are created with non-recursive `mkdir --`; `mkdir -p` is not used.

The test sudo boundaries are complete fail-closed allowlists. They log every argument as a separate delimited field, allow only the exact cask operations and pre-existing scenario-specific privileged vectors, reject unknown vectors with status 97, and inject failures for `mkdir`, `chown`, and `chmod` to prove later mutations and cask updates stop.

## Acceptance criteria

- The automated tests fail before the implementation and pass afterward.
- `nrs` repairs the current `/usr/local/bin` state without recursive changes.
- Docker Desktop upgrades from 4.84.0 to the current declared cask version.
- `brew outdated --cask --greedy` reports no declared cask as outdated.
- Docker Desktop is restarted and `docker info` succeeds.
