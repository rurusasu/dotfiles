# Task 3: Nix flake and host/system-manager wiring report

## Scope

Implemented only the Task 3 wiring changes in these files:

- `nix/flakes/lib/hosts.nix`
- `nix/flakes/hosts.nix`
- `nix/flakes/home.nix`
- `nix/hosts/darwin/default.nix`
- `nix/system-manager/default.nix`

This report is the required Task 3 delivery artifact. Unrelated dirty files
(`flake.lock`, Task 1 PowerShell/report changes, and `.codex`) were not edited
or staged.

## Implementation

- `mkNixos` reads `DOTFILES_USER`, falls back to `nixos`, and assigns the
  selected Home Manager user an `imports = [ homeModulePath ]` module.
- The helper provides `isWSL = false` by default and allows
  `homeExtraSpecialArgs` to override it. WSL is now the only caller that passes
  `isWSL = true`.
- NixOS callers use the flat `home/wsl.nix` and `home/linux.nix` modules.
- Standalone Home Manager uses `home/darwin.nix` for Darwin and `home/linux.nix`
  for Linux, retaining `isWSL = false`.
- nix-darwin imports `home/darwin.nix`; system-manager imports
  `home/linux.nix`. Existing Home Manager, overlay, special-argument, and
  dynamic-user settings remain in place.

## Validation

Passed:

- `nixfmt` on all five wiring files.
- `bats tests/bash/flake_outputs.bats` (8/8 passed; Bats emitted its existing
  minimum-version warning for `run --separate-stderr`).
- `nix flake show`.
- `nix eval --impure --raw '.#nixosConfigurations.nixos.config.system.build.toplevel.drvPath'`.
- `nix eval --impure --raw '.#homeConfigurations."x86_64-linux".activationPackage.drvPath'`.
- `DOTFILES_NIXOS_HARDWARE_CONFIG="$PWD/nix/tests/hardware-configuration.nix" nix eval --impure --raw '.#nixosConfigurations.linux.config.system.build.toplevel.drvPath'`.
- `DOTFILES_USER=codex DOTFILES_HOME=/Users/codex nix eval --impure --raw '.#darwinConfigurations.macos.config.system.build.toplevel.drvPath'`.

## Environment-limited checks

The exact native Linux command from the brief,

```bash
DOTFILES_NIXOS_HARDWARE_CONFIG=/dev/null nix eval --impure --raw '.#nixosConfigurations.linux.config.system.build.toplevel.drvPath'
```

fails before module evaluation because `/dev/null` is an empty file and Nix
parses it as a module (`syntax error, unexpected end of file`). The repository's
`nix/tests/hardware-configuration.nix` evaluation fixture was used instead and
the configuration evaluated successfully.

The exact Darwin command without environment values reaches the pre-existing
dynamic-user validation with empty `DOTFILES_USER` and `DOTFILES_HOME`. Supplying
those required values as shown above evaluates the Darwin toplevel successfully.

## Out-of-scope focused-test failures

Running the broader focused set (`home_layout.bats`, `flake_outputs.bats`,
`linux_config.bats`, and `macos_config.bats`) yielded 44/46 passing. The two
failures are outside the five Task 3 wiring files:

- `home_layout.bats` expects `nix/home/README.md`, which is absent.
- `linux_config.bats` expects the Darwin `nrs` alias inline in
  `nix/hosts/darwin/default.nix`; Task 3 intentionally moves it into the
  required `nix/home/darwin.nix` module.
