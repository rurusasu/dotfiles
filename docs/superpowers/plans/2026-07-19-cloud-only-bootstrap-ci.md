# Cloud-only Cross-platform Bootstrap CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the permanently queued Windows/macOS self-hosted bootstrap jobs with GitHub-hosted contract jobs, while retaining real declarative builds and Linux Docker runtime E2E.

**Architecture:** A new `Protected Bootstrap E2E` workflow runs the existing PowerShell contract suite on `windows-2025`, the existing Bats suite plus a real nix-darwin build on ARM64 `macos-15`, and a stable aggregate check on `ubuntu-24.04`. Existing Linux destructive E2E remains the runtime authority; Windows/macOS Docker Desktop startup remains enforced by each local installer but is explicitly outside standard hosted-runner CI.

**Tech Stack:** GitHub Actions YAML, PowerShell/Pester, Bash/Bats, Nix Flakes, nix-darwin, Markdown, GitHub pull requests.

## Global Constraints

- CI must use only standard GitHub-hosted runners and require no registered runner, Environment approval, repository secret, or personal machine.
- The required `Protected Bootstrap E2E` workflow must run on every pull request and must not use `pull_request.paths` filtering.
- Keep the top-level workflow name and aggregate job check name exactly `Protected Bootstrap E2E`.
- Use `windows-2025`, ARM64 `macos-15`, and `ubuntu-24.04` runner labels.
- Windows/macOS contract jobs must finish within 30 minutes; the aggregate job must finish within 5 minutes.
- Fork pull requests must run with read-only repository permissions.
- Windows and macOS jobs must record `runtime=not-applicable-on-github-hosted-runner`; they must not emit empty Docker versions as successful runtime evidence.
- Do not weaken or remove `ci-bootstrap-e2e-linux.yml`; Ubuntu, Debian, and NixOS remain the real Docker/Compose runtime E2E.
- Do not add Docker Offload, an external CI vendor, or another virtual machine provider.
- Historical dated design specs may describe the old decision, but active workflows and operational docs must not require `self-hosted`, `dotfiles-e2e`, or `destructive-e2e`.

---

### Task 1: Replace the self-hosted workflow with hosted bootstrap contracts

**Files:**

- Create: `.github/workflows/ci-bootstrap-e2e-hosted.yml`
- Delete: `.github/workflows/ci-bootstrap-e2e-self-hosted.yml`
- Modify: `scripts/powershell/tests/CiWorkflow.Tests.ps1`

**Interfaces:**

- Consumes: Pester 5.6.1, `scripts/powershell/tests/Invoke-Tests.ps1 -MinimumCoverage 0`, UTF-8 Bats with Homebrew Bash and GNU coreutils, `darwinConfigurations.macos.system`, and pinned `actions/checkout`, `cachix/install-nix-action`, and `actions/upload-artifact` actions already used by the repository.
- Produces: hosted jobs named `Windows Bootstrap Contract`, `macOS Bootstrap Contract`, and aggregate check `Protected Bootstrap E2E`.
- Produces artifacts: `windows-bootstrap-contract-<run>-<attempt>` and `macos-bootstrap-contract-<run>-<attempt>` containing `sha`, `runner_image`, `layer`, and `runtime` fields.

- [ ] **Step 1: Replace the old workflow expectations with failing hosted-runner tests**

In `scripts/powershell/tests/CiWorkflow.Tests.ps1`, replace the three `It` blocks beginning with `should protect destructive Windows and macOS self-hosted jobs`, `should run both real self-hosted installers twice`, and `should document dedicated destructive runner security and cleanup` with these two blocks:

```powershell
    It 'should run bootstrap contracts exclusively on GitHub-hosted runners' {
        $oldWorkflowPath = Join-Path $script:repoRoot ".github/workflows/ci-bootstrap-e2e-self-hosted.yml"
        $workflowPath = Join-Path $script:repoRoot ".github/workflows/ci-bootstrap-e2e-hosted.yml"

        $oldWorkflowPath | Should -Not -Exist
        $workflowPath | Should -Exist

        $workflow = Get-Content -LiteralPath $workflowPath -Raw
        $workflow | Should -Match 'name:\s+Protected Bootstrap E2E'
        $workflow | Should -Match 'runs-on:\s+windows-2025'
        $workflow | Should -Match 'runs-on:\s+macos-15'
        $workflow | Should -Match 'runs-on:\s+ubuntu-24\.04'
        $workflow | Should -Not -Match 'runs-on:\s*\[?self-hosted'
        $workflow | Should -Not -Match 'dotfiles-e2e'
        $workflow | Should -Not -Match 'destructive-e2e'
        $workflow | Should -Not -Match 'head\.repo\.full_name == github\.repository'
        $workflow | Should -Not -Match '(?m)^\s+paths:\s*$'
        $workflow | Should -Match 'permissions:\s*\r?\n\s+contents:\s+read'
        ([regex]::Matches($workflow, 'timeout-minutes:\s+30')).Count | Should -Be 2
        $workflow | Should -Match 'timeout-minutes:\s+5'
    }

    It 'should aggregate Windows and macOS contracts with explicit non-runtime attestations' {
        $workflowPath = Join-Path $script:repoRoot ".github/workflows/ci-bootstrap-e2e-hosted.yml"
        $workflow = Get-Content -LiteralPath $workflowPath -Raw

        $workflow | Should -Match "Install-Module -Name Pester -RequiredVersion '5\.6\.1'"
        $workflow | Should -Match 'Invoke-Tests\.ps1 -MinimumCoverage 0 -OutputFile windows-contract-junit\.xml'
        $workflow | Should -Not -Match 'Invoke-Tests\.ps1[^\r\n]*-IncludeIntegration'
        $workflow | Should -Match 'brew install bash bats-core coreutils'
        $workflow | Should -Match 'brew --prefix bash\)/bin'
        $workflow | Should -Match 'brew --prefix coreutils\)/libexec/gnubin'
        $workflow | Should -Match 'LC_ALL:\s+en_US\.UTF-8'
        $workflow | Should -Match 'bats tests/bash'
        $workflow | Should -Match 'nix build \.#darwinConfigurations\.macos\.system --impure --no-link'
        ([regex]::Matches($workflow, 'runtime=not-applicable-on-github-hosted-runner')).Count | Should -Be 2
        $workflow | Should -Match 'needs:\s*\[windows, macos\]'
        $workflow | Should -Match 'name:\s+Protected Bootstrap E2E'
        $workflow | Should -Match 'needs\.windows\.result'
        $workflow | Should -Match 'needs\.macos\.result'
        ([regex]::Matches($workflow, 'actions/upload-artifact@[0-9a-f]{40}')).Count | Should -Be 2
        ([regex]::Matches($workflow, 'github\.event\.pull_request\.head\.sha')).Count | Should -BeGreaterOrEqual 2
    }
```

- [ ] **Step 2: Run the focused test to verify RED**

Run:

```bash
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path scripts/powershell/tests/CiWorkflow.Tests.ps1 \
  -MinimumCoverage 0
```

Expected: FAIL because `.github/workflows/ci-bootstrap-e2e-self-hosted.yml` still exists and `.github/workflows/ci-bootstrap-e2e-hosted.yml` does not.

- [ ] **Step 3: Delete the self-hosted workflow and add the hosted workflow**

Delete `.github/workflows/ci-bootstrap-e2e-self-hosted.yml` and create `.github/workflows/ci-bootstrap-e2e-hosted.yml` with this content:

```yaml
name: Protected Bootstrap E2E

on:
  pull_request:
    branches: [main]

concurrency:
  group: protected-bootstrap-${{ github.event.pull_request.number }}
  cancel-in-progress: true

permissions:
  contents: read

env:
  TESTED_SHA: ${{ github.event.pull_request.head.sha }}

jobs:
  windows:
    name: Windows Bootstrap Contract
    runs-on: windows-2025
    timeout-minutes: 30
    steps:
      - name: Checkout exact PR head
        uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
        with:
          ref: ${{ github.event.pull_request.head.sha }}
          persist-credentials: false

      - name: Install pinned Pester
        shell: pwsh
        run: |
          Set-StrictMode -Version Latest
          $ErrorActionPreference = 'Stop'
          Install-Module -Name Pester -RequiredVersion '5.6.1' -Scope CurrentUser -Force -SkipPublisherCheck

      - name: Run Windows bootstrap contracts
        shell: pwsh
        run: |
          Set-StrictMode -Version Latest
          $ErrorActionPreference = 'Stop'
          & .\scripts\powershell\tests\Invoke-Tests.ps1 -MinimumCoverage 0 -OutputFile windows-contract-junit.xml
          if ($LASTEXITCODE -ne 0) {
            throw "Windows bootstrap contracts failed: $LASTEXITCODE"
          }

      - name: Write Windows contract attestation
        if: always()
        shell: pwsh
        run: |
          @(
            "sha=$env:TESTED_SHA"
            "runner_image=$env:ImageOS-$env:ImageVersion"
            "layer=windows-contract"
            "runtime=not-applicable-on-github-hosted-runner"
          ) | Set-Content -LiteralPath windows-contract-attestation.txt -Encoding utf8

      - name: Upload Windows contract results
        uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        if: always()
        with:
          name: windows-bootstrap-contract-${{ github.run_id }}-${{ github.run_attempt }}
          path: |
            windows-contract-attestation.txt
            windows-contract-junit.xml
          if-no-files-found: warn

  macos:
    name: macOS Bootstrap Contract
    runs-on: macos-15
    timeout-minutes: 30
    env:
      DOTFILES_USER: runner
      DOTFILES_HOME: /Users/runner
      LANG: en_US.UTF-8
      LC_ALL: en_US.UTF-8
    steps:
      - name: Checkout exact PR head
        uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
        with:
          ref: ${{ github.event.pull_request.head.sha }}
          persist-credentials: false

      - name: Install Nix
        uses: cachix/install-nix-action@8aa03977d8d733052d78f4e008a241fd1dbf36b3 # v31.10.6
        with:
          github_access_token: ${{ secrets.GITHUB_TOKEN }}

      - name: Install Bash, Bats, and GNU coreutils
        run: |
          brew install bash bats-core coreutils
          {
            echo "$(brew --prefix bash)/bin"
            echo "$(brew --prefix coreutils)/libexec/gnubin"
          } >> "$GITHUB_PATH"

      - name: Run POSIX bootstrap contracts
        run: bats tests/bash

      - name: Build macOS declarative output
        run: nix build .#darwinConfigurations.macos.system --impure --no-link

      - name: Verify provider coverage
        run: nix build .#package-support-report --no-link

      - name: Write macOS contract attestation
        if: always()
        run: |
          {
            echo "sha=$TESTED_SHA"
            echo "runner_image=$ImageOS-$ImageVersion"
            echo "layer=macos-contract"
            echo "runtime=not-applicable-on-github-hosted-runner"
          } > macos-contract-attestation.txt

      - name: Upload macOS contract results
        uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        if: always()
        with:
          name: macos-bootstrap-contract-${{ github.run_id }}-${{ github.run_attempt }}
          path: macos-contract-attestation.txt

  complete:
    name: Protected Bootstrap E2E
    if: always()
    needs: [windows, macos]
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - name: Require every hosted bootstrap contract
        env:
          WINDOWS_RESULT: ${{ needs.windows.result }}
          MACOS_RESULT: ${{ needs.macos.result }}
        run: |
          set -euo pipefail
          test "$WINDOWS_RESULT" = success
          test "$MACOS_RESULT" = success
```

- [ ] **Step 4: Format the changed workflow and test files**

Run:

```bash
nix fmt
git diff --check
```

Expected: both commands exit 0; the workflow stays on hosted runner labels and the PowerShell file remains UTF-8 without BOM and CRLF-formatted.

- [ ] **Step 5: Run the focused tests to verify GREEN**

Run:

```bash
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path scripts/powershell/tests/CiWorkflow.Tests.ps1 \
  -MinimumCoverage 0
```

Expected: PASS, including the two new hosted bootstrap contract tests.

- [ ] **Step 6: Commit the hosted workflow**

```bash
git add \
  .github/workflows/ci-bootstrap-e2e-hosted.yml \
  .github/workflows/ci-bootstrap-e2e-self-hosted.yml \
  scripts/powershell/tests/CiWorkflow.Tests.ps1
git commit -m "ci: replace self-hosted bootstrap E2E"
```

### Task 2: Document the cloud-only guarantee boundary

**Files:**

- Modify: `tests/bash/bootstrap_docs.bats`
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/scripts/powershell/testing.md`
- Modify: `docs/superpowers/specs/2026-07-17-cross-platform-bootstrap-design.md`
- Delete: `docs/ci/self-hosted-bootstrap-runners.md`

**Interfaces:**

- Consumes: workflow filename `.github/workflows/ci-bootstrap-e2e-hosted.yml` and aggregate name `Protected Bootstrap E2E` from Task 1.
- Produces: an operational documentation contract that distinguishes hosted Windows/macOS contract tests from hosted Linux runtime E2E.

- [ ] **Step 1: Write failing documentation contract tests**

Replace the last assertion in `README documents all bootstrap entrypoints and reruns` and add a new test in `tests/bash/bootstrap_docs.bats`:

```bash
@test "README documents all bootstrap entrypoints and reruns" {
	grep -q 'install.cmd' "$REPO_ROOT/README.md"
	[ "$(grep -c './install.sh' "$REPO_ROOT/README.md")" -ge 2 ]
	grep -q 'DOTFILES_ALLOW_USER_ONLY=1' "$REPO_ROOT/README.md"
	grep -Eqi 're-run|rerun|再実行' "$REPO_ROOT/README.md"
	grep -q 'GitHub-hosted' "$REPO_ROOT/README.md"
	! grep -q 'self-hosted-bootstrap-runners.md' "$REPO_ROOT/README.md"
}

@test "operational docs require only hosted bootstrap CI" {
	[ ! -e "$REPO_ROOT/docs/ci/self-hosted-bootstrap-runners.md" ]
	grep -q 'ci-bootstrap-e2e-hosted.yml' "$REPO_ROOT/docs/architecture.md"
	grep -q 'Protected Bootstrap E2E' "$REPO_ROOT/docs/scripts/powershell/testing.md"
	for file in \
		"$REPO_ROOT/README.md" \
		"$REPO_ROOT/docs/architecture.md" \
		"$REPO_ROOT/docs/scripts/powershell/testing.md"; do
		! grep -Eq 'dotfiles-e2e|destructive-e2e|ci-bootstrap-e2e-self-hosted.yml' "$file"
	done
}
```

- [ ] **Step 2: Run the documentation tests to verify RED**

Run:

```bash
bats tests/bash/bootstrap_docs.bats
```

Expected: FAIL because README and operational docs still reference the self-hosted workflow and runner guide.

- [ ] **Step 3: Replace the README CI section**

In `README.md`, replace the paragraph under `### 成功条件と CI` with:

```markdown
「コマンドが終了した」だけでは成功扱いにしません。必須 CLI、chezmoi drift、Docker daemon、Compose 全サービス、`docker run --rm hello-world` を acceptance で確認します。CI は GitHub-hosted Actions だけで完結し、Windows は PowerShell/Pester、macOS は Bats と nix-darwin build で installer 契約を検証します。Ubuntu、Debian、NixOS は hosted E2E で installer を 2 回適用し、Docker と Compose の runtime acceptance まで実行します。

標準の hosted Windows/macOS runner では Docker Desktop の VM を起動しないため、その実機固有部分は各 OS で one-command installer を実行した際の acceptance が判定します。ローカル acceptance が失敗した場合、installer はセットアップ成功を表示しません。
```

- [ ] **Step 4: Replace the architecture workflow table and merge policy**

In `docs/architecture.md`, replace the CI table row for `ci-bootstrap-e2e-self-hosted.yml` and the two paragraphs below the table with:

```markdown
| `ci-bootstrap-e2e-hosted.yml` | hosted Windows/macOS/Linux | Pester/Bats、nix-darwin build、`Protected Bootstrap E2E` aggregate |

Windows/macOS は標準 hosted runner で installer の分岐、順序、失敗伝播、冪等性と宣言 output を検証します。Docker Desktop、WSL2、nix-darwin switch の実機適用は nested virtualization と OS 制約のため CI では実行せず、one-command installer 末尾の local acceptance が判定します。

Ubuntu、Debian、NixOS の hosted Linux job は 1 周目で clean bootstrap、2 周目で idempotency を検証し、各周回の後に runtime acceptance を実行します。pull request では hosted contract、declarative build、Linux runtime E2E の全checkが成功し、approval待ちやqueued jobがないことをmerge条件にします。
```

- [ ] **Step 5: Replace the PowerShell testing policy**

In `docs/scripts/powershell/testing.md`, replace the self-hosted row and the paragraphs following the test strategy table with:

```markdown
| `ci-bootstrap-e2e-hosted.yml` | hosted Windows/macOS/Linux | Windows/macOS contract と `Protected Bootstrap E2E` aggregate |

Windows hosted contract は Pester 5.6.1 を固定して `Invoke-Tests.ps1 -MinimumCoverage 0` を実行し、外部 process wrapper を mock した状態で entrypoint、handler order、failure propagation、second-run behavior を検証します。実機アプリを要求する `Integration.Tests.ps1` は含めません。macOS hosted contract は Homebrew Bash、UTF-8 locale、GNU coreutils を用意して Bats、nix-darwin build、provider coverageを実行します。

Docker Desktop と WSL2 の実runtimeは標準hosted runnerでは起動しません。Docker、Compose、chezmoiの共通runtimeは `ci-bootstrap-e2e-linux.yml` がUbuntu、Debian、NixOSで検証し、Windows/macOS実機固有のruntimeは各installer末尾のacceptanceが失敗を返します。
```

Replace the sentence beginning `保護された Windows self-hosted E2E` with:

```markdown
`Protected Bootstrap E2E` は hosted Windows の全Pester contract、hosted macOSの全Bats contractとnix-darwin buildを集約します。実機変更やEnvironment approvalを要求しないため、fork pull requestを含めrunner待ちなしで完了します。
```

- [ ] **Step 6: Mark the old design decision as superseded and delete the runner guide**

Immediately below the title in `docs/superpowers/specs/2026-07-17-cross-platform-bootstrap-design.md`, add:

```markdown
> **CI update (2026-07-19):** The Windows/macOS self-hosted E2E sections are superseded by [Cloud-only Cross-platform Bootstrap CI Design](./2026-07-19-cloud-only-bootstrap-ci-design.md). The installer and declarative-layer design remains current.
```

Delete `docs/ci/self-hosted-bootstrap-runners.md`.

- [ ] **Step 7: Format documentation and verify GREEN**

Run:

```bash
nix fmt
bats tests/bash/bootstrap_docs.bats
git diff --check
```

Expected: all commands exit 0; operational docs contain no old workflow filename, Environment name, or custom runner label.

- [ ] **Step 8: Commit the documentation boundary**

```bash
git add \
  README.md \
  docs/architecture.md \
  docs/scripts/powershell/testing.md \
  docs/superpowers/specs/2026-07-17-cross-platform-bootstrap-design.md \
  docs/ci/self-hosted-bootstrap-runners.md \
  tests/bash/bootstrap_docs.bats
git commit -m "docs: define hosted bootstrap CI guarantees"
```

### Task 3: Verify the complete cloud-only change locally

**Files:**

- Verify only; do not create or modify source files intentionally.

**Interfaces:**

- Consumes: hosted workflow and docs contracts from Tasks 1 and 2.
- Produces: fresh local evidence for shell tests, the cross-platform PowerShell workflow contract, Nix evaluation, nix-darwin build, formatting, and repository cleanliness. The complete Windows-only Pester suite runs in Task 1's `windows-2025` job and is verified remotely in Task 4.

- [ ] **Step 1: Run the complete Bats suite**

Run:

```bash
bats tests/bash
```

Expected: every Bats test passes with zero failures.

- [ ] **Step 2: Run the cross-platform PowerShell workflow contract locally**

Run:

```bash
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 \
  -Path scripts/powershell/tests/CiWorkflow.Tests.ps1 \
  -MinimumCoverage 0
```

Expected: every test in `CiWorkflow.Tests.ps1` passes with zero failures. Do not run the complete Windows handler suite on macOS because its fixtures intentionally use Windows drive and process semantics; `Windows Bootstrap Contract` runs the non-integration suite with pinned Pester 5.6.1 on `windows-2025`.

- [ ] **Step 3: Evaluate all flake checks**

Run:

```bash
nix flake check --no-build
```

Expected: exit 0 with no evaluation warnings.

- [ ] **Step 4: Build the Apple Silicon nix-darwin output**

Run:

```bash
DOTFILES_USER="$USER" DOTFILES_HOME="$HOME" \
  nix build .#darwinConfigurations.macos.system --impure --no-link
```

Expected: exit 0 and no activation of the local macOS system.

- [ ] **Step 5: Run repository formatting and whitespace checks**

Run:

```bash
pre-commit run --all-files
git diff --check
git status --short
```

Expected: pre-commit and `git diff --check` exit 0; `git status --short` is empty. If treefmt changes a file, inspect that exact diff, commit only the formatter output with `git commit -am "style: format hosted bootstrap CI"`, and repeat this step.

### Task 4: Update PR #429, complete cloud checks, and merge

**Files:**

- Remote branch: `agent/fix-macos-bootstrap`
- Pull request: `https://github.com/rurusasu/dotfiles/pull/429`
- Obsolete queued run: `https://github.com/rurusasu/dotfiles/actions/runs/29648123783`

**Interfaces:**

- Consumes: clean, verified local branch and GitHub-connected repository access.
- Produces: PR #429 containing the exact local tree, no queued self-hosted run, successful required checks for the latest head SHA, and a merged pull request.

- [ ] **Step 1: Verify the local branch and remote PR scope before publishing**

Run:

```bash
git status --short --branch
git log --oneline origin/main..HEAD
git diff --stat origin/main...HEAD
```

Expected: the branch contains the macOS bootstrap fix, cloud-only design/plan, hosted workflow, tests, and docs only; the worktree is clean.

- [ ] **Step 2: Publish the exact local tree to the existing PR branch**

Invoke `github:yeet` and update `agent/fix-macos-bootstrap`, preserving PR #429 rather than opening another pull request. Because the local and connector-created remote histories differ, compare file trees rather than commit hashes:

```bash
git fetch origin agent/fix-macos-bootstrap
git diff --exit-code HEAD origin/agent/fix-macos-bootstrap --
```

Expected after publication: `git diff --exit-code` returns 0.

- [ ] **Step 3: Cancel the obsolete self-hosted workflow run**

Cancel Actions run `29648123783` through the connected GitHub app or authenticated GitHub UI. Do not register a runner and do not approve `destructive-e2e`.

Expected: both old destructive jobs become `cancelled`, and no self-hosted job is queued for the latest PR head.

- [ ] **Step 4: Verify required-check configuration**

Inspect the `main` branch ruleset or branch protection. The stable required status must be the aggregate job `Protected Bootstrap E2E`; remove obsolete required names `Windows Destructive E2E` and `macOS Destructive E2E` if present.

Expected: branch protection references only checks that the new hosted workflow can produce.

- [ ] **Step 5: Monitor every workflow for the latest PR head**

Confirm successful completion of at least:

```text
Protected Bootstrap E2E
Windows Bootstrap Contract
macOS Bootstrap Contract
Bootstrap Build
Linux Bootstrap E2E
Nix CI
PowerShell CI
Chezmoi CI
devcontainer CI
```

If any current-head GitHub Actions check fails, invoke `github:gh-fix-ci`, inspect the failing logs, reproduce locally when possible, add a regression test, publish the fix, and restart this step. Do not treat an old-head cancelled run as a current failure.

- [ ] **Step 6: Verify before merge**

Invoke `superpowers:verification-before-completion` and confirm:

```text
PR head SHA equals the tested SHA shown by GitHub.
All required current-head checks are success.
No current-head check is queued, waiting, pending approval, or in progress.
PR #429 is mergeable and has no unresolved review request.
```

- [ ] **Step 7: Merge PR #429**

Merge `https://github.com/rurusasu/dotfiles/pull/429` using the repository's allowed merge method. Then verify `merged: true`, record the merge commit SHA, and confirm no required work remains on the feature branch.

Expected: PR #429 is merged into `main` and the cloud-only bootstrap CI runs without a registered self-hosted runner.
