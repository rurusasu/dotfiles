# Task 4 Report: WSL bootstrap and Home Manager layout

## Scope

- Removed obsolete Home Manager generation from `scripts/sh/nixos-wsl-postinstall.sh`.
- Updated WSL install documentation and the WSL module gnome-keyring comment.
- Added `nix/home/README.md` for the canonical flat Home Manager layout.

## Implementation

The WSL postinstall script now creates only `nix/hosts/wsl` and retains its
existing per-file `if [[ ! -f ... ]]` guards for `default.nix`,
`configuration.nix`, and `hardware-configuration.nix`. It no longer creates
`nix/home/users/<user>.nix`, `nix/home/wsl/default.nix`, or
`nix/profiles/home`.

The documentation identifies `nix/home/wsl.nix` as the canonical, repository-
managed WSL Home Manager module. It also documents that `DOTFILES_USER` takes
precedence and NixOS falls back to `nixos` when it is absent.

`nix/home/README.md` defines the layout and import direction
`caller -> <os>.nix -> common.nix`, prohibits `default.nix` and `users.nix`,
defines ownership with `nix/packages/sets.nix` and `chezmoi/`, documents secret
handling, and provides an OS-specific-setting checklist.

## Validation

- `bash -n scripts/sh/nixos-wsl-postinstall.sh` — pass.
- `nixfmt --check nix/modules/wsl/default.nix` — pass.
- `git diff --check` — pass.
- Obsolete-path scan over the Task 4 files — no matches.
- `bats tests/bash/bootstrap_entrypoint.bats tests/bash/bootstrap_docs.bats tests/bash/home_layout.bats` — 10/10 pass.

## Notes

- `shellcheck scripts/sh/nixos-wsl-postinstall.sh` still reports existing
  SC2034 (`SYSTEM` unused) and SC2016 (intentional single-quoted `bash -c`
  payload) diagnostics on unchanged lines; they are outside Task 4 scope.
- Existing unrelated changes were left untouched: dirty `flake.lock`, Task 1
  report, PowerShell test, and untracked `.codex` content.
