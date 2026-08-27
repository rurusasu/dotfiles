# Task 2 Report: Home Manager OS Modules

## Status

Implemented Task 2's flat Home Manager OS modules. Caller wiring remains
unchanged for Task 3.

## Files

Created:

- `nix/home/darwin.nix`
- `nix/home/linux.nix`
- `nix/home/wsl.nix`

Modified:

- `nix/home/common.nix` — updated consumer comments for the flat OS modules.

Removed:

- `nix/home/linux/users.nix`
- `nix/home/users/nixos.nix`
- `nix/home/wsl/default.nix`
- `nix/home/wsl/users.nix`

The WSL module retains its fcitx5 profile, session variables, NixOS aliases,
and fcitx5 and GNOME Keyring user services. It accepts the caller-provided
`isWSL` argument and imports `./common.nix`.

## Tests

Command:

```bash
bats tests/bash/home_layout.bats tests/bash/linux_config.bats tests/bash/macos_config.bats
```

Result: 36 passed, 2 failed (expected follow-up failures):

- `nix/home/README.md` is intentionally deferred to Task 4.
- `nix/hosts/darwin/default.nix` has not yet imported `../../home/darwin.nix`.
  This is caller wiring owned by Task 3.

The new flat-file import assertions and Linux/WSL alias assertions pass.

Additional checks:

```bash
nixfmt --check nix/home/common.nix nix/home/darwin.nix nix/home/linux.nix nix/home/wsl.nix
git diff --check
```

Both completed successfully.

## Concerns

- Task 3 must update consumers before Nix evaluation can use the new modules.
- Existing documentation and comments outside Task 2 still mention the removed
  WSL paths and are intentionally unchanged.

## Review Follow-up

Updated the stale gnome-keyring comment in `nix/modules/wsl/default.nix` to
reference `nix/home/wsl.nix`.

Focused validation completed successfully:

```bash
nix-instantiate --parse nix/modules/wsl/default.nix
git diff --check
```
