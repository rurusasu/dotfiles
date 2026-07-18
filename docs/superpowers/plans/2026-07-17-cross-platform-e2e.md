# Windows Integration and Destructive E2E Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect Windows to the shared acceptance contract and prove one-command convergence with destructive Linux, NixOS, Windows, and macOS E2E checks.

**Architecture:** Preserve Windows handlers and add a platform-specific verifier adapter. Hosted runners perform builds plus destructive Linux tests; dedicated protected self-hosted machines perform Docker Desktop/WSL and macOS nix-darwin tests. All destructive jobs run twice and attest the tested head SHA.

**Tech Stack:** PowerShell/Pester, Bash/Bats, GitHub Actions, Docker, WSL2, NixOS VM tests, self-hosted runners.

## Global Constraints

- Fork PRs never execute self-hosted jobs.
- Self-hosted jobs require the `destructive-e2e` Environment and dedicated `dotfiles-e2e` labels.
- Windows and macOS runtime E2E must run the real installers twice.
- A skipped destructive test is not equivalent to a successful Full support test.

---

### Task 1: Add Windows environment acceptance

**Files:**

- Create: `scripts/powershell/Test-Environment.ps1`
- Create: `scripts/powershell/tests/Test-Environment.Tests.ps1`
- Modify: `scripts/powershell/install.ps1`

**Interfaces:**

- Produces: `Test-DotfilesEnvironment -Runtime` returning a `SetupResult`-compatible outcome.
- Consumes existing external-command wrappers; it does not directly invoke executables in handler code.

- [ ] **Step 1: Write failing Pester tests**

Add Pester cases with mocked `Get-Command` and `Invoke-ExternalCommand`:

```powershell
It 'should run Docker chezmoi and WSL acceptance checks' {
    Test-DotfilesEnvironment -Runtime
    Should -Invoke Invoke-ExternalCommand -ParameterFilter { $FilePath -eq 'docker' -and $ArgumentList -contains 'hello-world' }
    Should -Invoke Invoke-ExternalCommand -ParameterFilter { $FilePath -eq 'chezmoi' -and $ArgumentList -contains '--dry-run' }
    Should -Invoke Invoke-ExternalCommand -ParameterFilter { $FilePath -eq 'wsl' }
}

It 'should fail when a required command is missing' {
    Mock Get-Command { $null } -ParameterFilter { $Name -eq 'nvim' }
    { Test-DotfilesEnvironment } | Should -Throw '*Missing command: nvim*'
}
```

- [ ] **Step 2: Verify RED**

Run:

```powershell
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/Test-Environment.Tests.ps1 -MinimumCoverage 0
```

Expected: FAIL because `Test-DotfilesEnvironment` is undefined.

- [ ] **Step 3: Implement the verifier**

```powershell
function Test-DotfilesEnvironment {
    [CmdletBinding()]
    param([switch]$Runtime)
    $required = @('winget','git','gh','chezmoi','rg','fd','jq','nvim','node','python','go','rustup','docker','wsl')
    foreach ($name in $required) {
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "Missing command: $name" }
    }
    Invoke-ExternalCommand -FilePath 'docker' -ArgumentList @('info') -ThrowOnError
    Invoke-ExternalCommand -FilePath 'docker' -ArgumentList @('compose','version') -ThrowOnError
    Invoke-ExternalCommand -FilePath 'chezmoi' -ArgumentList @('apply','--dry-run') -ThrowOnError
    if ($Runtime) {
        Invoke-ExternalCommand -FilePath 'docker' -ArgumentList @('run','--rm','hello-world') -ThrowOnError
    }
}
```

Invoke it after all install phases and before printing completion.

- [ ] **Step 4: Verify and commit**

Run the targeted test and `scripts/powershell/tests/Invoke-Tests.ps1 -MinimumCoverage 0`.

Expected: PASS.

```bash
git add scripts/powershell/Test-Environment.ps1 scripts/powershell/install.ps1 scripts/powershell/tests/Test-Environment.Tests.ps1
git commit -m "test: verify the installed Windows environment"
```

### Task 2: Add hosted build and destructive Linux workflows

**Files:**

- Create: `.github/workflows/ci-bootstrap-build.yml`
- Create: `.github/workflows/ci-bootstrap-e2e-linux.yml`
- Modify: `.github/workflows/ci-nix.yml`
- Test: `scripts/powershell/tests/CiWorkflow.Tests.ps1`

**Interfaces:**

- Produces required checks `Bootstrap Build`, `Ubuntu Destructive`, `Debian systemd Destructive`, `NixOS VM`.

- [ ] **Step 1: Add failing workflow contract tests**

Assert path filters, pinned action SHAs, timeouts, two installer invocations, runtime verification, and artifact
upload with `if: always()`.

- [ ] **Step 2: Verify RED**

Run the targeted `CiWorkflow.Tests.ps1` test file.

Expected: FAIL because workflows are absent.

- [ ] **Step 3: Implement build matrix**

Build `darwinConfigurations.macos.system`, both `systemConfigs`, both NixOS toplevels, standalone HM, and
`package-support-report`. Use hosted runners and never start Docker Desktop in this workflow.

- [ ] **Step 4: Implement destructive Linux jobs**

Ubuntu job core steps:

```yaml
- run: ./install.sh
- run: ./scripts/sh/verify-environment.sh --runtime
- run: ./install.sh
- run: ./scripts/sh/verify-environment.sh --runtime
```

Debian must boot a privileged systemd-nspawn environment and run the same four commands inside it. NixOS
must use a NixOS VM test that executes two system activations and `docker run --rm hello-world`.

- [ ] **Step 5: Verify syntax/contracts and commit**

Run:

```bash
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/CiWorkflow.Tests.ps1 -MinimumCoverage 0
nix flake check --no-build
```

Expected: PASS.

```bash
git add .github/workflows/ci-bootstrap-build.yml .github/workflows/ci-bootstrap-e2e-linux.yml .github/workflows/ci-nix.yml scripts/powershell/tests/CiWorkflow.Tests.ps1
git commit -m "ci: test destructive Linux bootstrap paths"
```

### Task 3: Add protected self-hosted Windows and macOS E2E

**Files:**

- Create: `.github/workflows/ci-bootstrap-e2e-self-hosted.yml`
- Modify: `scripts/powershell/tests/CiWorkflow.Tests.ps1`
- Create: `docs/ci/self-hosted-bootstrap-runners.md`

**Interfaces:**

- Produces checks `Windows Destructive E2E` and `macOS Destructive E2E` for the PR head SHA.

- [ ] **Step 1: Write failing security/workflow tests**

Require same-repository PR condition, Environment name, exact runner labels, concurrency, timeout, two real
installer runs, runtime verifier, and SHA artifact.

- [ ] **Step 2: Verify RED**

Run targeted CI workflow tests.

Expected: FAIL because the workflow is absent.

- [ ] **Step 3: Implement the protected workflow**

Use this gate on both jobs:

```yaml
if: >-
  github.event_name == 'pull_request' &&
  github.event.pull_request.head.repo.full_name == github.repository
environment: destructive-e2e
```

Windows uses `runs-on: [self-hosted, Windows, X64, dotfiles-e2e]`, runs `install.cmd` twice, then
`Test-Environment.ps1 -Runtime`. macOS uses `[self-hosted, macOS, ARM64, dotfiles-e2e]`, runs
`./install.sh` twice, then `verify-environment.sh --runtime`.

Each job writes `${{ github.event.pull_request.head.sha }}` plus Nix generation, Docker version, and support
report hash to an attestation text file uploaded with `actions/upload-artifact` pinned by SHA.

- [ ] **Step 4: Document exact runner setup**

Document repository registration, labels, dedicated account, `destructive-e2e` approval, no personal secrets,
sudo/elevation prerequisites, Docker license acceptance, clean-bootstrap reset, and runner removal.

- [ ] **Step 5: Verify and commit**

Run CI workflow Pester tests and `git diff --check`.

Expected: PASS.

```bash
git add .github/workflows/ci-bootstrap-e2e-self-hosted.yml scripts/powershell/tests/CiWorkflow.Tests.ps1 docs/ci/self-hosted-bootstrap-runners.md
git commit -m "ci: run protected Windows and macOS bootstrap E2E"
```

### Task 4: Update user and architecture documentation

**Files:**

- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/nix/package-management.md`
- Modify: `docs/scripts/powershell/testing.md`
- Test: `tests/bash/bootstrap_docs.bats`

**Interfaces:**

- Documents exactly three Full support entrypoints: `install.cmd`, macOS `./install.sh`, Linux `./install.sh`.

- [ ] **Step 1: Add failing documentation tests**

Add these documentation assertions:

```bash
@test "README documents all bootstrap entrypoints and reruns" {
  grep -q 'install.cmd' "$REPO_ROOT/README.md"
  [ "$(grep -c './install.sh' "$REPO_ROOT/README.md")" -ge 2 ]
  grep -q 'DOTFILES_ALLOW_USER_ONLY=1' "$REPO_ROOT/README.md"
  grep -qi 're-run\|rerun\|再実行' "$REPO_ROOT/README.md"
  grep -q 'self-hosted-bootstrap-runners.md' "$REPO_ROOT/README.md"
  grep -q 'package-support-report' "$REPO_ROOT/docs/nix/package-management.md"
}
```

- [ ] **Step 2: Verify RED**

Run: `bats tests/bash/bootstrap_docs.bats`

Expected: FAIL because docs describe the old macOS-only dispatcher.

- [ ] **Step 3: Update documentation**

Replace old flow diagrams with the four declarative layers, document:

```text
Windows: install.cmd
macOS: ./install.sh
NixOS/Ubuntu/Debian: ./install.sh
Other Linux: DOTFILES_ALLOW_USER_ONLY=1 ./install.sh
```

Include failure diagnostics and the fact that Full support success requires runtime acceptance.

- [ ] **Step 4: Run complete local verification**

```bash
bats tests/bash
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -MinimumCoverage 0
nix fmt -- --fail-on-change
nix flake check --no-build
nix build .#package-support-report
nix build .#darwinConfigurations.macos.system --impure --no-link
nix build .#systemConfigs.ubuntu --impure --no-link
nix build .#systemConfigs.debian --impure --no-link
git diff --check
```

Expected: every command exits 0.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/architecture.md docs/nix/package-management.md docs/scripts/powershell/testing.md tests/bash/bootstrap_docs.bats
git commit -m "docs: document one-command setup on every OS"
```

### Task 5: Execute destructive acceptance and record results

**Files:**

- No source changes unless a test-first defect fix is required.

**Interfaces:**

- Consumes configured `dotfiles-e2e` Windows/macOS runners and GitHub Environment approval.
- Produces green checks for the exact PR head SHA.

- [ ] **Step 1: Push the implementation branch and open the PR**

Use the repository publishing workflow; do not merge yet.

- [ ] **Step 2: Approve the protected Environment jobs**

Confirm both jobs target the exact PR head SHA and same-repository branch before approval.

- [ ] **Step 3: Read all E2E logs and attestations**

Expected: Ubuntu, Debian, NixOS, Windows, and macOS each show first run, runtime acceptance, second run, runtime
acceptance, and an attestation matching the head SHA.

- [ ] **Step 4: Fix failures only with systematic debugging and TDD**

For any failure, capture the failing phase, add a minimal automated reproducer, verify RED, implement one root
cause fix, and rerun the affected local and remote suites.

- [ ] **Step 5: Merge only after all required checks are green**

Expected: no skipped Full support E2E job and no pending Environment deployment.
