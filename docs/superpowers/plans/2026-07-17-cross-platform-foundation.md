# Cross-platform Catalog and Flake Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Nix package catalog describe every OS provider explicitly and add pinned flake inputs/apps required by macOS and generic Linux.

**Architecture:** Extend the existing `sets.nix` SSOT instead of creating a second manifest. Generate a machine-readable provider report and fail evaluation when a Windows package lacks either a Darwin/Linux provider or an explicit unsupported reason. Pin nix-darwin, nix-homebrew, and System Manager in the existing flake-parts graph.

**Tech Stack:** Nix flakes, flake-parts, jq, Pester, GitHub Actions.

## Global Constraints

- Home Manager remains the shared macOS/Linux user layer.
- `windows/winget/packages.json`, npm JSON, and pnpm JSON remain generated files.
- True Windows-only components stay supported only on Windows with an explicit reason for both other OSes.
- GUI and CLI products use separate catalog entries.
- All behavior changes follow red-green-refactor and end in focused commits.

---

### Task 1: Pin cross-platform system inputs and expose runner apps

**Files:**

- Modify: `flake.nix`
- Create: `nix/flakes/apps.nix`
- Modify: `nix/flakes/default.nix`
- Test: `tests/bash/flake_outputs.bats`

**Interfaces:**

- Produces: flake inputs `nix-darwin`, `nix-homebrew`, `system-manager`.
- Produces: apps `.#darwin-rebuild` and `.#system-manager` that use locked inputs.

- [ ] **Step 1: Write failing flake wiring tests**

```bash
@test "flake pins darwin homebrew and system manager inputs" {
  run grep -E 'nix-darwin|nix-homebrew|system-manager' "$REPO_ROOT/flake.nix"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -ge 3 ]
}

@test "flake imports locked platform runner apps" {
  grep -q './apps.nix' "$REPO_ROOT/nix/flakes/default.nix"
  grep -q 'darwin-rebuild' "$REPO_ROOT/nix/flakes/apps.nix"
  grep -q 'system-manager' "$REPO_ROOT/nix/flakes/apps.nix"
}
```

- [ ] **Step 2: Verify the tests fail for missing inputs/apps**

Run: `bats tests/bash/flake_outputs.bats`

Expected: FAIL because `apps.nix` and the three inputs do not exist.

- [ ] **Step 3: Add pinned inputs and app wrappers**

Add to `flake.nix`:

```nix
nix-darwin = {
  url = "github:nix-darwin/nix-darwin/master";
  inputs.nixpkgs.follows = "nixpkgs";
};
nix-homebrew.url = "github:zhaofengli/nix-homebrew";
system-manager = {
  url = "github:numtide/system-manager";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Create `nix/flakes/apps.nix`:

```nix
{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      apps = {
        darwin-rebuild = inputs.nix-darwin.apps.${system}.darwin-rebuild;
        system-manager = inputs.system-manager.apps.${system}.default;
      };
    };
}
```

Import `./apps.nix` from `nix/flakes/default.nix`.

- [ ] **Step 4: Update the lock and verify app metadata**

Run:

```bash
nix flake lock --update-input nix-darwin --update-input nix-homebrew --update-input system-manager
bats tests/bash/flake_outputs.bats
nix flake show --json | jq -e '.apps."aarch64-darwin"."darwin-rebuild" and .apps."x86_64-linux"."system-manager"'
```

Expected: Bats PASS and jq exits 0.

- [ ] **Step 5: Commit**

```bash
git add flake.nix flake.lock nix/flakes/apps.nix nix/flakes/default.nix tests/bash/flake_outputs.bats
git commit -m "feat: pin cross-platform system managers"
```

### Task 2: Add explicit provider metadata to the package SSOT

**Files:**

- Modify: `nix/packages/sets.nix`
- Test: `scripts/powershell/tests/PackageCatalog.Tests.ps1`
- Test: `tests/bash/package_catalog.bats`

**Interfaces:**

- Produces: `supportReport`, `darwinCasks`, `linuxSystemModules`, and `providerErrors` attrs from `sets.nix`.
- Preserves: `all`, `wingetMap`, `windowsOnly`, npm/pnpm metadata consumed by existing exporters.

- [ ] **Step 1: Add failing provider-coverage tests**

Add Pester assertions that `Docker.DockerDesktop`, `dprint.dprint`, `hadolint.hadolint`,
`Microsoft.VisualStudioCode`, `OpenAI.Codex`, `Oven-sh.Bun`, and `zig.zig` are no longer in
`windowsOnly.winget`. Add a Bats test:

```bash
@test "catalog defines provider coverage outputs" {
  grep -q 'supportReport' "$REPO_ROOT/nix/packages/sets.nix"
  grep -q 'providerErrors' "$REPO_ROOT/nix/packages/sets.nix"
  grep -q 'darwinCasks' "$REPO_ROOT/nix/packages/sets.nix"
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
bats tests/bash/package_catalog.bats
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/PackageCatalog.Tests.ps1 -MinimumCoverage 0
```

Expected: FAIL because provider attrs and migrations are absent.

- [ ] **Step 3: Extend each catalog entry with provider/support fields**

Use this exact shape for normal entries:

```nix
codex = {
  pkg = pkgs.codex;
  winget = "OpenAI.Codex";
  category = "llm";
  support = {
    windows = { provider = "winget"; };
    darwin = { provider = "nix"; };
    linux = { provider = "nix"; };
  };
};
```

Use this exact shape for casks and system modules:

```nix
docker-desktop = {
  winget = "Docker.DockerDesktop";
  category = "system";
  support = {
    windows = { provider = "winget"; };
    darwin = { provider = "homebrew-cask"; cask = "docker-desktop"; };
    linux = { provider = "system-manager"; systemModule = "docker"; };
  };
};
```

Use explicit unsupported reasons for OS-native entries:

```nix
windows-terminal = {
  winget = "Microsoft.WindowsTerminal";
  category = "windows-system";
  support = {
    windows = { provider = "winget"; };
    darwin = { unsupported = "Windows shell host"; };
    linux = { unsupported = "Windows shell host"; };
  };
};
```

Apply these migrations:

| Windows ID                               | Darwin                       | Linux                                            |
| ---------------------------------------- | ---------------------------- | ------------------------------------------------ |
| `AgileBits.1Password`                    | cask `1password`             | Nix `_1password-gui`                             |
| `Anthropic.Claude`                       | cask `claude`                | unsupported: no supported Linux desktop provider |
| `TheBrowserCompany.Arc`                  | cask `arc`                   | unsupported: vendor has no Linux build           |
| `Docker.DockerDesktop`                   | cask `docker-desktop`        | system module `docker`                           |
| `GitHub.Copilot`                         | unsupported: Windows app     | unsupported: Windows app                         |
| `dprint.dprint`                          | Nix `dprint`                 | Nix `dprint`                                     |
| `hadolint.hadolint`                      | Nix `hadolint`               | Nix `hadolint`                                   |
| `Google.Chrome`                          | cask `google-chrome`         | Nix `google-chrome`                              |
| `Microsoft.PowerToys`                    | unsupported                  | unsupported                                      |
| `Microsoft.VCRedist.2015+.x64`           | unsupported                  | unsupported                                      |
| `Microsoft.VisualStudio.2022.BuildTools` | unsupported                  | unsupported                                      |
| `Microsoft.VisualStudioCode`             | cask `visual-studio-code`    | Nix `vscode`                                     |
| `Microsoft.WindowsTerminal`              | unsupported                  | unsupported                                      |
| `Microsoft.WSL`                          | unsupported                  | unsupported                                      |
| `OpenAI.Codex`                           | Nix `codex`                  | Nix `codex`                                      |
| `StablyAI.Orca`                          | unsupported: Windows package | unsupported: Windows package                     |
| `TablePlus.TablePlus`                    | cask `tableplus`             | unsupported: no pinned Nix provider              |
| `Oven-sh.Bun`                            | Nix `bun`                    | Nix `bun`                                        |
| `zig.zig`                                | Nix `zig`                    | Nix `zig`                                        |

Keep Microsoft Store Codex desktop separate from Codex CLI and give it explicit unsupported reasons.

- [ ] **Step 4: Derive provider outputs and errors**

Add these derivations, using `builtins.hasAttr` for dynamic platform lookup:

```nix
supportReport = lib.mapAttrs (_: entry: entry.support) catalog;
darwinCasks = lib.mapAttrsToList (_: entry: entry.support.darwin.cask)
  (lib.filterAttrs (_: entry: entry.support.darwin ? cask) catalog);
linuxSystemModules = lib.mapAttrsToList (_: entry: entry.support.linux.systemModule)
  (lib.filterAttrs (_: entry: entry.support.linux ? systemModule) catalog);
providerErrors = lib.concatMap
  (name:
    lib.concatMap
      (platform:
        let
          hasPlatform = builtins.hasAttr platform catalog.${name}.support;
          platformData = if hasPlatform then catalog.${name}.support.${platform} else { };
          resolved =
            (platformData ? provider)
            || ((platformData ? unsupported) && platformData.unsupported != "");
        in
        lib.optional (!resolved) "${name}: missing ${platform} provider or unsupported reason")
      [ "windows" "darwin" "linux" ])
  (lib.attrNames catalog);
```

Update existing catalog readers so entries without Nix or Winget providers remain valid:

```nix
p = catalog.${n}.pkg or null;
wingetMap = lib.filterAttrs (_: v: v != null)
  (lib.mapAttrs (_: v: v.winget or null) catalog);
```

- [ ] **Step 5: Verify GREEN and generated Windows compatibility**

Run:

```bash
bats tests/bash/package_catalog.bats
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/PackageCatalog.Tests.ps1 -MinimumCoverage 0
nix build .#winget-export -o /tmp/winget-export
diff <(jq -S . /tmp/winget-export/winget/packages.json) <(jq -S . windows/winget/packages.json)
```

Expected: tests PASS; the diff identifies only deterministic ordering/metadata updates that Task 3 regenerates.

- [ ] **Step 6: Commit**

```bash
git add nix/packages/sets.nix scripts/powershell/tests/PackageCatalog.Tests.ps1 tests/bash/package_catalog.bats
git commit -m "feat: model package providers across operating systems"
```

### Task 3: Generate and enforce the package support report

**Files:**

- Create: `nix/packages/support-report.nix`
- Modify: `nix/flakes/packages.nix`
- Modify: `nix/packages/winget.nix`
- Modify: `windows/winget/packages.json`
- Modify: `.github/workflows/ci-consistency.yml`
- Test: `tests/bash/package_catalog.bats`

**Interfaces:**

- Produces: `.#package-support-report` containing `support.json`.
- Produces: flake check `package-provider-coverage` that fails on `providerErrors`.

- [ ] **Step 1: Add a failing report build test**

```bash
@test "support report derivation and CI gate are wired" {
  grep -q 'package-support-report' "$REPO_ROOT/nix/flakes/packages.nix"
  grep -q 'package-provider-coverage' "$REPO_ROOT/.github/workflows/ci-consistency.yml"
}
```

- [ ] **Step 2: Verify RED**

Run: `bats tests/bash/package_catalog.bats`

Expected: FAIL because the derivation and CI step do not exist.

- [ ] **Step 3: Implement the derivation and check**

Create `nix/packages/support-report.nix`:

```nix
{ pkgs, lib, gwqSrc ? null }:
let
  sets = import ./sets.nix { inherit pkgs lib gwqSrc; };
  report = builtins.toJSON sets.supportReport;
  errors = builtins.toJSON sets.providerErrors;
in
pkgs.runCommand "package-support-report" { } ''
  mkdir -p "$out"
  printf '%s' '${report}' | ${pkgs.jq}/bin/jq . > "$out/support.json"
  printf '%s' '${errors}' | ${pkgs.jq}/bin/jq . > "$out/errors.json"
  test "$(${pkgs.jq}/bin/jq length "$out/errors.json")" -eq 0
''
```

Expose it as `packages.package-support-report` and `checks.package-provider-coverage` in
`nix/flakes/packages.nix`.

- [ ] **Step 4: Regenerate manifests and add CI commands**

Run:

```bash
nix build .#winget-export -o /tmp/winget-export
cp /tmp/winget-export/winget/packages.json windows/winget/packages.json
cp /tmp/winget-export/npm/packages.json windows/npm/packages.json
cp /tmp/winget-export/pnpm/packages.json windows/pnpm/packages.json
```

Add CI:

```yaml
- name: Verify package provider coverage
  run: |
    nix build .#package-support-report -o /tmp/package-support-report
    jq -e 'length == 0' /tmp/package-support-report/errors.json
```

- [ ] **Step 5: Verify all foundation checks**

Run:

```bash
bats tests/bash/package_catalog.bats tests/bash/flake_outputs.bats
nix flake check --no-build
nix build .#package-support-report
nix build .#winget-export
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 6: Commit**

```bash
git add nix/packages/support-report.nix nix/flakes/packages.nix nix/packages/winget.nix windows .github/workflows/ci-consistency.yml tests/bash/package_catalog.bats
git commit -m "test: enforce cross-platform package coverage"
```
