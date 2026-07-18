# gwq nixpkgs Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the repository-local `gwq` derivation with nixpkgs' `pkgs.gwq` on Unix platforms while keeping Windows out of winget management.

**Architecture:** `nix/packages/sets.nix` remains the package catalog SSOT, but its `gwq` entry will reference `pkgs.gwq`. The standalone `gwq-src` flake input and all `gwqSrc` plumbing will be removed. Provider resolution will continue to select Nix for Linux/macOS and the reviewed unsupported reason for Windows.

**Tech Stack:** Nix flakes, nixpkgs, Home Manager, nix-darwin, NixOS/System Manager, Pester 5, Bash bats, jq.

## Global Constraints

- `gwq` must use `pkgs.gwq` from the locked nixpkgs revision.
- Linux/NixOS/WSL and macOS must use the Nix provider.
- Windows must not receive a `gwq` winget/npm/pnpm entry.
- `reviewedUnsupported.windows.gwq` must remain the explicit Windows provider reason.
- Remove the local `gwq-src` input and `nix/packages/gwq/default.nix`; do not keep a fallback derivation.
- Preserve unrelated working-tree changes, especially `.codex/config.toml`.

---

### Task 1: Add the migration regression test first

**Files:**

- Modify: `/Users/ktome1995/Program/dotfiles/scripts/powershell/tests/PackageCatalog.Tests.ps1` in `Describe 'Package catalog consistency'` → `Context 'Latest package policy'`

**Interfaces:**

- Consumes: the tracked catalog, flake, provider wiring files, and generated Windows manifest.
- Produces: a failing Pester test that defines the required nixpkgs-backed `gwq` behavior.

- [ ] **Step 1: Replace the old source-input test with the desired behavior test.**

Replace the existing `It 'should source gwq from a flake input so nix flake update can move it forward'` block with:

```powershell
        It 'should use nixpkgs gwq and keep it out of Windows package providers' {
            $flake = Get-Content -LiteralPath (Join-Path $script:repoRoot "flake.nix") -Raw
            $sets = Get-Content -LiteralPath $script:setsPath -Raw
            $manifest = Get-Content -LiteralPath $script:wingetJsonPath -Raw | ConvertFrom-Json
            $wiringPaths = @(
                "nix/packages/sets.nix",
                "nix/flakes/packages.nix",
                "nix/home/common.nix",
                "nix/darwin/default.nix",
                "nix/modules/host/default.nix",
                "nix/packages/winget.nix",
                "nix/packages/support-report.nix"
            )
            $wiring = $wiringPaths |
                ForEach-Object { Get-Content -LiteralPath (Join-Path $script:repoRoot $_) -Raw } |
                Out-String

            $flake | Should -Not -Match 'gwq-src'
            $wiring | Should -Not -Match 'gwqSrc|gwq-src'
            $sets | Should -Match '(?s)gwq\s*=\s*\{.*?pkg\s*=\s*pkgs\.gwq;.*?winget\s*=\s*null;'
            $sets | Should -Match '(?s)reviewedUnsupported\s*=\s*\{.*?windows\s*=\s*lib\.genAttrs\s*\[.*?"gwq"'

            $wingetSource = @($manifest.Sources | Where-Object { $_.SourceDetails.Name -eq 'winget' }) | Select-Object -First 1
            @($wingetSource.Packages | Where-Object { $_.PackageIdentifier -eq 'gwq' }).Count | Should -Be 0
            (Join-Path $script:repoRoot "nix/packages/gwq/default.nix") | Should -Not -Exist
        }
```

- [ ] **Step 2: Run only the affected Pester file and verify the test fails for the old implementation.**

Run:

```bash
pwsh -NoProfile -Command "& ./scripts/powershell/tests/Invoke-Tests.ps1 -Path ./scripts/powershell/tests/PackageCatalog.Tests.ps1 -MinimumCoverage 0"
```

Expected: FAIL in the new `gwq` test because the old `gwq-src` input and local derivation still exist.

---

### Task 2: Switch the catalog to nixpkgs and remove local source plumbing

**Files:**

- Modify: `/Users/ktome1995/Program/dotfiles/nix/packages/sets.nix`
- Modify: `/Users/ktome1995/Program/dotfiles/flake.nix`
- Modify: `/Users/ktome1995/Program/dotfiles/nix/flakes/packages.nix`
- Modify: `/Users/ktome1995/Program/dotfiles/nix/home/common.nix`
- Modify: `/Users/ktome1995/Program/dotfiles/nix/darwin/default.nix`
- Modify: `/Users/ktome1995/Program/dotfiles/nix/modules/host/default.nix`
- Modify: `/Users/ktome1995/Program/dotfiles/nix/packages/winget.nix`
- Modify: `/Users/ktome1995/Program/dotfiles/nix/packages/support-report.nix`
- Delete: `/Users/ktome1995/Program/dotfiles/nix/packages/gwq/default.nix`

**Interfaces:**

- Consumes: nixpkgs exposing `pkgs.gwq` after the lock update.
- Produces: a catalog entry that resolves `gwq` through Nix on Unix and no local source input dependency anywhere in the flake.

- [ ] **Step 1: Change the `gwq` catalog entry.**

In `nix/packages/sets.nix`, change the entry to:

```nix
    gwq = {
      pkg = pkgs.gwq;
      winget = null;
      category = "dev";
    };
```

Remove the top-level `gwqSrc ? null` argument and remove the `import ./gwq/default.nix (...)` expression.

- [ ] **Step 2: Remove the standalone flake input.**

Delete this block from `flake.nix`:

```nix
    gwq-src = {
      url = "github:d-kuro/gwq";
      flake = false;
    };
```

- [ ] **Step 3: Remove every `gwqSrc` argument and forwarding expression.**

In each listed file, remove the argument declaration or attribute assignment without changing the surrounding package/provider logic:

```text
nix/flakes/packages.nix
nix/home/common.nix
nix/darwin/default.nix
nix/modules/host/default.nix
nix/packages/winget.nix
nix/packages/support-report.nix
```

For example, the `sets` import in `nix/flakes/packages.nix` becomes:

```nix
      sets = import ../packages/sets.nix {
        pkgs = pkgs.extend workmuxOverlay;
        inherit lib;
      };
```

The `gwqSrc = ...` line is removed from all other `sets`, `unfreeSets`, `packageSupportReport`, and `winget-export` imports.

- [ ] **Step 4: Delete the obsolete local derivation.**

Delete `/Users/ktome1995/Program/dotfiles/nix/packages/gwq/default.nix` with `apply_patch`.

- [ ] **Step 5: Run the migration test before updating the lock and verify only the nixpkgs availability remains as a possible failure.**

Run the same Pester command from Task 1. Expected: the static catalog/provider assertions pass, while Nix evaluation may still fail until Task 3 updates the lock.

---

### Task 3: Update nixpkgs and regenerate the Windows manifests

**Files:**

- Modify: `/Users/ktome1995/Program/dotfiles/flake.lock`
- Possibly modify: `/Users/ktome1995/Program/dotfiles/windows/winget/packages.json`
- Possibly modify: `/Users/ktome1995/Program/dotfiles/windows/npm/packages.json`
- Possibly modify: `/Users/ktome1995/Program/dotfiles/windows/pnpm/packages.json`

**Interfaces:**

- Consumes: the updated catalog from Task 2.
- Produces: a lock file whose nixpkgs package set contains `gwq`, plus generated manifests synchronized with the catalog.

- [ ] **Step 1: Update only the nixpkgs flake input.**

Run:

```bash
nix flake lock --update-input nixpkgs
```

Expected: `flake.lock` moves the nixpkgs node to a revision containing `pkgs.gwq`; unrelated flake inputs remain unchanged.

- [ ] **Step 2: Confirm the locked package set exposes `gwq`.**

Run:

```bash
nix eval --impure --json --expr 'let f = builtins.getFlake (toString ./.); pkgs = import f.inputs.nixpkgs { system = "x86_64-linux"; config.allowUnfree = true; }; in { inherit (pkgs) gwq; }'
```

Expected: JSON evaluation succeeds and contains a `gwq` derivation.

- [ ] **Step 3: Generate the Windows manifests from the updated catalog.**

Run:

```bash
nix build .#winget-export -o /tmp/dotfiles-gwq-winget-export
cp /tmp/dotfiles-gwq-winget-export/winget/packages.json windows/winget/packages.json
cp /tmp/dotfiles-gwq-winget-export/npm/packages.json windows/npm/packages.json
cp /tmp/dotfiles-gwq-winget-export/pnpm/packages.json windows/pnpm/packages.json
```

Expected: no generated manifest contains a `gwq` package entry. If the generated files are byte-for-byte unchanged, leave them unchanged.

---

### Task 4: Run focused and repository-level verification

**Files:**

- Test: `/Users/ktome1995/Program/dotfiles/scripts/powershell/tests/PackageCatalog.Tests.ps1`
- Test: `/Users/ktome1995/Program/dotfiles/tests/bash/package_catalog.bats`

**Interfaces:**

- Consumes: the completed migration and generated artifacts.
- Produces: evidence that Nix provider resolution, Windows exclusion, formatting, and package support coverage all pass.

- [ ] **Step 1: Run the focused Pester test.**

```bash
pwsh -NoProfile -Command "& ./scripts/powershell/tests/Invoke-Tests.ps1 -Path ./scripts/powershell/tests/PackageCatalog.Tests.ps1 -MinimumCoverage 0"
```

Expected: exit code 0 and all tests in `PackageCatalog.Tests.ps1` pass.

- [ ] **Step 2: Run the Bash catalog tests.**

```bash
bats tests/bash/package_catalog.bats
```

Expected: all catalog tests pass.

- [ ] **Step 3: Verify provider coverage and the absence of a Windows `gwq` entry.**

```bash
nix build .#package-support-report
test "$(jq 'length' result/errors.json 2>/dev/null || jq 'length' result/package-support-report/errors.json)" -eq 0
jq -e '[.Sources[] | select(.SourceDetails.Name == "winget") | .Packages[] | select(.PackageIdentifier == "gwq")] | length == 0' windows/winget/packages.json
```

Expected: provider errors length is 0 and the jq expression returns true. If the build output path differs, inspect `result` and run the equivalent jq check against the generated error file.

- [ ] **Step 4: Run Nix formatting and flake checks.**

```bash
nix fmt -- --fail-on-change
nix flake check --no-build
```

Expected: formatting reports no changes and flake checks complete successfully.

- [ ] **Step 5: Review the final diff and preserve unrelated changes.**

```bash
git status --short
git diff --stat
rg -n 'gwq-src|gwqSrc|nix/packages/gwq/default.nix' flake.nix nix scripts/powershell/tests/PackageCatalog.Tests.ps1
```

Expected: only the intended migration files are changed; the search returns no obsolete `gwq-src`/`gwqSrc` references, and `.codex/config.toml` remains untouched by this work.
