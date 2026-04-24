# Nix Platform Guards Design

## Problem

`inputs.systems` defines 4 platforms (x86_64-linux, aarch64-linux, x86_64-darwin, aarch64-darwin), but some packages in the catalog (e.g., `slack` on aarch64-linux) are not available on all platforms. `nix flake check --all-systems` will fail when evaluating these packages.

## Solution

Modify the `resolve` helper in `sets.nix` to filter packages based on `meta.platforms` from nixpkgs. Packages whose `meta.platforms` does not include the current `pkgs.system` are excluded automatically.

## Design

### Change: `nix/packages/sets.nix` — `resolve` helper only

Before:

```nix
resolve = names: map (n: catalog.${n}.pkg) names;
```

After:

```nix
resolve =
  names:
  builtins.filter (p: p != null) (
    map (
      n:
      let
        p = catalog.${n}.pkg;
      in
      if builtins.elem pkgs.system (p.meta.platforms or lib.platforms.all) then p else null
    ) names
  );
```

### Behavior

- `meta.platforms` defined and includes current system → package included
- `meta.platforms` defined but does NOT include current system → package excluded
- `meta.platforms` undefined → falls back to `lib.platforms.all` (included on all platforms)

### What is NOT changed

- Catalog entries — no `platforms` field added
- Consumers (`home/packages.nix`, `winget.nix`, `flakes/packages.nix`) — no changes
- `wingetMap` derivation — unaffected (derived from `catalog.*.winget`, not `resolve`)

### Verification

- `nix flake check --all-systems` must pass (currently only x86_64-linux is verified)
- winget-export consistency must be maintained

## Out of scope

- Windows package manager strategy (winget vs pnpm vs npm) — separate issue
- `windowsOnly` section restructuring — separate issue
