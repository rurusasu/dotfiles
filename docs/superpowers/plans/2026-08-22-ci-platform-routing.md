# Platform-Aware GitHub Actions Routing Implementation Plan

> **Status:** Historical plan. The obsolete WezTerm installer path mentioned here was removed; current routing follows the declarative nix-darwin Homebrew cask configuration.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Route GitHub Actions by processing dependency and independently target Linux, Darwin, WSL, and Windows while preserving required check contexts.

**Architecture:** A versioned JSON manifest describes path-to-output rules, a Python 3.14 detector computes the union for changed paths, and a local composite action exposes those outputs to existing workflows. Heavy platform jobs use job-level gates; a lightweight Contract CI owns routing, Python, Bats, and actionlint validation.

**Tech Stack:** GitHub Actions YAML, Python 3.14 standard library, unittest, Bats 1.13.0, PowerShell/Pester 6, Nix, actionlint 1.7.12.

**Spec:** docs/superpowers/specs/2026-08-22-ci-platform-routing-design.md

## Global Constraints

- Treat Linux, Darwin, WSL, and Windows as four independent platform outputs.
- WSL host orchestration may enable both wsl and windows; never alias WSL to Linux or Windows.
- Preserve the required check names Lint (Pester chezmoi), Format (.tmpl BOM check), and Render guard (op unauthenticated).
- Keep required and aggregate workflows running; skip expensive work at job level.
- workflow_dispatch must run every platform job.
- Use only repository-local code or commit-SHA-pinned GitHub Actions.
- Unknown ordinary paths run Contract CI but do not enable a heavy platform job.
- Invalid manifests and unsafe paths fail closed with a non-zero exit status.
- Do not modify installer, package, or user configuration behavior.

---

### Task 1: Normalize the Existing PowerShell Test Baseline

**Files:**

- Normalize: scripts/powershell/tests/CiWorkflow.Tests.ps1
- Normalize: scripts/powershell/tests/HermesBootstrapEntrypoint.Tests.ps1
- Normalize: scripts/powershell/tests/Install.Entrypoint.Tests.ps1
- Normalize: scripts/powershell/tests/PackageCatalog.Tests.ps1

**Interfaces:**

- Consumes the existing .gitattributes CRLF working-tree rule.
- Produces a clean baseline without semantic PowerShell changes.

- [ ] **Step 1: Prove the current differences are line-ending-only**

```bash
git diff --ignore-space-at-eol --exit-code -- \
  scripts/powershell/tests/CiWorkflow.Tests.ps1 \
  scripts/powershell/tests/HermesBootstrapEntrypoint.Tests.ps1 \
  scripts/powershell/tests/Install.Entrypoint.Tests.ps1 \
  scripts/powershell/tests/PackageCatalog.Tests.ps1
```

Expected: exit 0 while git status reports the four paths modified.

- [ ] **Step 2: Normalize only those index entries**

```bash
git add --renormalize -- \
  scripts/powershell/tests/CiWorkflow.Tests.ps1 \
  scripts/powershell/tests/HermesBootstrapEntrypoint.Tests.ps1 \
  scripts/powershell/tests/Install.Entrypoint.Tests.ps1 \
  scripts/powershell/tests/PackageCatalog.Tests.ps1
git diff --cached --ignore-space-at-eol --exit-code
git diff --cached --check
```

Expected: both diff checks exit 0.

- [ ] **Step 3: Re-run the focused baseline**

```bash
pwsh -NoProfile -Command '& ./scripts/powershell/tests/Invoke-Tests.ps1 -Path @("./scripts/powershell/tests/CiWorkflow.Tests.ps1", "./scripts/powershell/tests/PackageCatalog.Tests.ps1", "./scripts/powershell/tests/HermesBootstrapEntrypoint.Tests.ps1", "./scripts/powershell/tests/Install.Entrypoint.Tests.ps1") -MinimumCoverage 0'
```

Expected: 90 passed, 0 failed, 3 Windows-only tests skipped.

- [ ] **Step 4: Commit**

```bash
git commit -m "chore: normalize PowerShell CI tests"
```

### Task 2: Build the Routing Manifest and Detector with TDD

**Files:**

- Create: ci/path-routing.json
- Create: scripts/python/detect_ci_changes.py
- Create: tests/python/test_detect_ci_changes.py

**Interfaces:**

- Produces route_paths(paths: Iterable[str], manifest_path: Path) -> dict[str, bool].
- Produces CLI flags --manifest, --paths-file, --github-output, and --all.
- Output keys are linux, darwin, wsl, windows, contract, nix, chezmoi, hermes, devcontainer, package_catalog.

- [ ] **Step 1: Write failing table-driven routing tests**

Use these exact scenarios:

```python
CASES = {
    "nix/packages/sets.nix": {
        "linux", "darwin", "wsl", "windows", "contract",
        "nix", "chezmoi", "package_catalog",
    },
    "nix/home/common.nix": {
        "linux", "darwin", "wsl", "contract", "nix", "chezmoi",
    },
    "scripts/sh/install-linux.sh": {"linux", "contract"},
    "scripts/sh/install-macos.sh": {"darwin", "contract"},
    "scripts/sh/nixos-wsl-postinstall.sh": {
        "wsl", "windows", "contract", "nix",
    },
    "scripts/powershell/handlers/Handler.NixOSWSL.ps1": {
        "wsl", "windows", "contract",
    },
    "chezmoi/dot_config/nvim/init.lua": {"contract", "chezmoi"},
    "docker/hermes-xapi-mcp/Dockerfile": {
        "linux", "darwin", "wsl", "windows", "contract", "hermes",
    },
}
```

Every result must contain all ten keys, and the true-key set must equal the expected set.

- [ ] **Step 2: Verify RED**

```bash
python3 -m unittest tests/python/test_detect_ci_changes.py -v
```

Expected: import or file-not-found failure because production files do not exist.

- [ ] **Step 3: Add union, safety, manifest, and CLI tests**

Add named tests with these exact assertions:

- test_multiple_paths_union_outputs routes install-linux.sh and install-macos.sh together and asserts both linux and darwin are true;
- test_unknown_path_enables_contract_only routes README.md and asserts contract is the only true output;
- test_absolute_path_is_rejected passes /tmp/file and asserts ValueError;
- test_parent_traversal_is_rejected passes ../flake.nix and asserts ValueError;
- test_unknown_manifest_output_is_rejected adds unsupported to a temporary manifest and asserts ValueError;
- test_all_flag_enables_every_output invokes the CLI with --all and asserts every JSON value is true;
- test_github_output_contains_lowercase_booleans writes to a temporary output file and compares its lines with the sorted expected name/value pairs.

CLI validation tests assert exit code 2 and an argparse error message.

- [ ] **Step 4: Implement the manifest**

Use this schema:

```json
{
  "version": 1,
  "outputs": [
    "linux",
    "darwin",
    "wsl",
    "windows",
    "contract",
    "nix",
    "chezmoi",
    "hermes",
    "devcontainer",
    "package_catalog"
  ],
  "rules": []
}
```

Populate explicit rules for:

- routing infrastructure: all ten outputs;
- flake.nix, flake.lock, nix/flakes/**: Linux, Darwin, WSL, contract, Nix;
- package SSOT and generators: all platforms, contract, Nix, Chezmoi, package catalog;
- windows/winget and windows/npm manifests: Windows, contract, package catalog;
- windows/pnpm manifest: Windows, WSL, contract, package catalog;
- nix/home/common.nix: Linux, Darwin, WSL, contract, Nix, Chezmoi;
- Linux Nix trees: Linux, contract, Nix;
- WSL Nix trees: WSL, contract, Nix;
- nix/darwin/**: Darwin, contract, Nix;
- nix/modules/host/**: Linux, WSL, contract, Nix;
- dcnvim.sh, install-wezterm-nightly.sh, uninstall-arc-browser.sh: consuming platforms, contract, Nix;
- Linux, Darwin, and WSL installer entrypoints: explicit platforms and contract;
- PowerShell WSL handlers: WSL, Windows, contract;
- other scripts/powershell/**: Windows, contract;
- Chezmoi OS metadata: all platforms, contract, Chezmoi;
- Chezmoi _windows, _darwin, and _linux files: matching platforms, contract, Chezmoi;
- other chezmoi/**: contract, Chezmoi;
- all Hermes Docker directories, Taskfile, Compose, and adapters: all platforms, contract, Hermes;
- .devcontainer/**, bootstrap.sh, dcnvim.sh: Linux, Darwin, Windows, contract, devcontainer;
- workflow, Taskfile, taskfiles, and CI test paths: contract.

Specific rules precede broad rules. Matching is union-based.

- [ ] **Step 5: Implement the Python 3.14 detector**

Use PurePosixPath.full_match(). Reject absolute paths, paths containing a parent traversal segment, and paths containing a backslash. Initialize all outputs false, force contract true, union matching rules, emit sorted JSON, and write lowercase booleans to GitHub output.

- [ ] **Step 6: Verify GREEN**

```bash
python3 -m unittest tests/python/test_detect_ci_changes.py -v
```

- [ ] **Step 7: Commit**

```bash
git add ci/path-routing.json scripts/python/detect_ci_changes.py tests/python/test_detect_ci_changes.py
git commit -m "feat: add platform-aware CI change detector"
```

### Task 3: Expose Routing Through a Local Composite Action

**Files:**

- Create: .github/actions/detect-ci-changes/action.yml
- Create: tests/python/test_detect_ci_action_contract.py

**Interfaces:**

- Inputs: base-sha, head-sha, run-all.
- Outputs: all ten detector outputs as lowercase booleans.
- Consumes the detector and routing manifest.
- Sets up Python 3.14 with actions/setup-python@ece7cb06caefa5fff74198d8649806c4678c61a1 before invoking the detector.

- [ ] **Step 1: Write the failing action contract**

Assert the action declares all inputs and outputs, pins the Python setup action, requests Python 3.14, runs git diff with --name-only --diff-filter=ACMR, invokes detect_ci_changes.py, and passes --github-output.

- [ ] **Step 2: Verify RED**

```bash
python3 -m unittest tests/python/test_detect_ci_action_contract.py -v
```

- [ ] **Step 3: Implement the action**

The composite action first sets up Python 3.14 with the pinned action. Its bash step must use set -euo pipefail. When run-all is true, invoke the detector with --all. Otherwise diff base-sha to head-sha into RUNNER_TEMP/ci-changed-paths.txt and invoke the detector with --paths-file and --github-output. Map each declared output from steps.detect.outputs.

- [ ] **Step 4: Verify GREEN and commit**

```bash
python3 -m unittest tests/python/test_detect_ci_changes.py tests/python/test_detect_ci_action_contract.py -v
git add .github/actions/detect-ci-changes/action.yml tests/python/test_detect_ci_action_contract.py
git commit -m "feat: expose CI routing as a composite action"
```

### Task 4: Add Lightweight Contract CI

**Files:**

- Create: .github/workflows/ci-contract.yml
- Create: tests/bash/ci_routing.bats
- Create: tests/python/test_ci_workflow_routing.py

**Interfaces:**

- Workflow and job name: CI Contract.
- Python action: actions/setup-python@ece7cb06caefa5fff74198d8649806c4678c61a1 with Python 3.14.
- actionlint: github.com/rhysd/actionlint/cmd/actionlint@v1.7.12.

- [ ] **Step 1: Write failing workflow contract tests**

Assert that the workflow runs on every pull request to main, watches routing files and all Bats/Python tests on push, pins setup-python, runs Python discovery and all Bats, and runs actionlint 1.7.12.

- [ ] **Step 2: Verify RED**

```bash
python3 -m unittest tests/python/test_ci_workflow_routing.py -v
```

- [ ] **Step 3: Add real-detector Bats scenarios**

Cover a Linux-only path, Darwin-only path, WSL+Windows path, and shared package path. Each test writes a temporary path file, invokes the detector, checks exit 0, and asserts the JSON booleans.

- [ ] **Step 4: Implement Contract CI**

Use the existing pinned checkout action, the pinned Python setup action, Bats 1.13.0 installation copied from Protected Bootstrap E2E, and pinned Go module installation for actionlint. Install Nix with the existing pinned cachix action so the complete Bats suite retains its current contracts without moving package evaluation into heavy build jobs.

- [ ] **Step 5: Verify GREEN and commit**

```bash
python3 -m unittest discover -s tests/python -v
bats --print-output-on-failure tests/bash
go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12
git add .github/workflows/ci-contract.yml tests/bash/ci_routing.bats tests/python/test_ci_workflow_routing.py
git commit -m "ci: add lightweight routing contract checks"
```

### Task 5: Correct Nix, Devcontainer, and Hermes Triggers

**Files:**

- Modify: .github/workflows/ci-nix.yml
- Modify: .github/workflows/ci-devcontainer.yml
- Modify: .github/workflows/ci-hermes-bootstrap.yml
- Modify: .pre-commit-config.yaml
- Modify: taskfiles/hermes/taskfile.yml
- Modify: scripts/powershell/tests/CiWorkflow.Tests.ps1
- Modify: tests/python/test_ci_workflow_routing.py

**Interfaces:**

- Nix CI watches Nix inputs and only Nix-embedded shell scripts.
- devcontainer CI does not start solely for arbitrary Bats changes.
- Hermes CI watches agent, browser, browser-mcp, xapi-mcp, and both platform adapters.

- [ ] **Step 1: Add failing assertions**

Require scripts/sh/** and tests/bash/** to be absent from Nix CI; require the three Nix-embedded scripts. Require tests/bash/** to be absent from devcontainer CI. Require xapi-mcp, hermes-agent.sh, Handler.HermesAgent.ps1, and the xapi Python contract in Hermes CI.

- [ ] **Step 2: Verify RED**

```bash
python3 -m unittest tests/python/test_ci_workflow_routing.py -v
```

- [ ] **Step 3: Implement minimal trigger changes**

Apply assertions to both push and pull request path lists. Extend the Hermes pre-commit regex and hermes:bootstrap:test task so xapi image contract changes execute tests/python/test_xapi_image_contract.py.

- [ ] **Step 4: Update the Pester workflow contract**

Replace assertions requiring tests/bash/** in devcontainer with assertions requiring Contract CI to watch and execute tests/bash. Keep dcnvim-specific devcontainer assertions.

- [ ] **Step 5: Verify GREEN and commit**

```bash
python3 -m unittest tests/python/test_ci_workflow_routing.py tests/python/test_xapi_image_contract.py -v
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/CiWorkflow.Tests.ps1 -MinimumCoverage 0
task hermes:bootstrap:test
git add .github/workflows/ci-nix.yml .github/workflows/ci-devcontainer.yml .github/workflows/ci-hermes-bootstrap.yml .pre-commit-config.yaml taskfiles/hermes/taskfile.yml scripts/powershell/tests/CiWorkflow.Tests.ps1 tests/python/test_ci_workflow_routing.py
git commit -m "ci: route Nix devcontainer and Hermes checks by dependency"
```

### Task 6: Gate Bootstrap Build by Linux and Darwin Outputs

**Files:**

- Modify: .github/workflows/ci-bootstrap-build.yml
- Modify: tests/python/test_ci_workflow_routing.py
- Modify: scripts/powershell/tests/CiWorkflow.Tests.ps1

**Interfaces:**

- changes outputs linux and darwin.
- Platform jobs depend on changes and use job-level conditions.
- Bootstrap Build aggregate accepts success or skipped, and rejects failure or cancellation.

- [ ] **Step 1: Write failing gate assertions**

Require a changes job, fetch-depth 0, local detector action, Linux/Darwin conditions, always-running complete job, dependency result environment variables, and routing-infrastructure paths in the workflow trigger.

- [ ] **Step 2: Verify RED**

```bash
python3 -m unittest tests/python/test_ci_workflow_routing.py -v
```

- [ ] **Step 3: Implement the gate**

Pass pull request base/head SHA or push before/current SHA to the action. Pass run-all true for workflow_dispatch. Add needs: changes and conditions to platform jobs. Make complete depend on changes, linux, darwin and accept only success or skipped platform results.

- [ ] **Step 4: Verify GREEN and commit**

```bash
python3 -m unittest tests/python/test_ci_workflow_routing.py -v
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/CiWorkflow.Tests.ps1 -MinimumCoverage 0
go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12 .github/workflows/ci-bootstrap-build.yml
git add .github/workflows/ci-bootstrap-build.yml tests/python/test_ci_workflow_routing.py scripts/powershell/tests/CiWorkflow.Tests.ps1
git commit -m "ci: gate bootstrap builds by target platform"
```

### Task 7: Gate Protected Bootstrap E2E by Windows and Darwin Outputs

**Files:**

- Modify: .github/workflows/ci-bootstrap-e2e-hosted.yml
- Modify: tests/python/test_ci_workflow_routing.py
- Modify: scripts/powershell/tests/CiWorkflow.Tests.ps1

**Interfaces:**

- changes outputs windows and darwin.
- Workflow remains active for every pull request and adds workflow_dispatch.
- Aggregate check name remains Protected Bootstrap E2E.

- [ ] **Step 1: Write failing protected-E2E assertions**

Require Windows and Darwin job conditions, complete needs changes/windows/macos, result variables, success-or-skipped acceptance, workflow_dispatch, and event-safe concurrency and tested SHA expressions.

- [ ] **Step 2: Verify RED**

```bash
python3 -m unittest tests/python/test_ci_workflow_routing.py -v
```

- [ ] **Step 3: Implement job-level gates**

Reuse the changes job contract from Bootstrap Build. Preserve exact tested-SHA checkout. In complete, use shell case statements that accept success or skipped and reject every other result.

- [ ] **Step 4: Verify GREEN and commit**

```bash
python3 -m unittest tests/python/test_ci_workflow_routing.py -v
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/CiWorkflow.Tests.ps1 -MinimumCoverage 0
go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12 .github/workflows/ci-bootstrap-e2e-hosted.yml
git add .github/workflows/ci-bootstrap-e2e-hosted.yml tests/python/test_ci_workflow_routing.py scripts/powershell/tests/CiWorkflow.Tests.ps1
git commit -m "ci: gate hosted bootstrap contracts by platform"
```

### Task 8: Gate Linux Bootstrap and NixOS WSL E2E

**Files:**

- Modify: .github/workflows/ci-bootstrap-e2e-linux.yml
- Modify: .github/workflows/ci-nixos-wsl.yml
- Modify: tests/python/test_ci_workflow_routing.py
- Modify: scripts/powershell/tests/CiWorkflow.Tests.ps1

**Interfaces:**

- Linux destructive and VM jobs run only when changes.linux is true.
- NixOS WSL switch runs only when changes.wsl is true and the existing same-repository security condition is true.
- workflow_dispatch forces both workflows to execute their platform jobs.

- [ ] **Step 1: Write failing Linux and WSL gate assertions**

Require both workflows to contain a changes job using the local detector with fetch-depth 0. Require ubuntu, debian, and nixos jobs to depend on changes and test the linux output. Require the WSL switch condition to combine the wsl output with the existing fork-PR repository comparison.

- [ ] **Step 2: Verify RED**

```bash
python3 -m unittest tests/python/test_ci_workflow_routing.py -v
```

- [ ] **Step 3: Implement the Linux and WSL gates**

Use the same base/head and run-all input contract as Bootstrap Build. Add routing infrastructure paths to both workflow-level path filters. Do not weaken the WSL fork-PR restriction.

- [ ] **Step 4: Verify GREEN and commit**

```bash
python3 -m unittest tests/python/test_ci_workflow_routing.py -v
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -Path scripts/powershell/tests/CiWorkflow.Tests.ps1 -MinimumCoverage 0
go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12 .github/workflows/ci-bootstrap-e2e-linux.yml .github/workflows/ci-nixos-wsl.yml
git add .github/workflows/ci-bootstrap-e2e-linux.yml .github/workflows/ci-nixos-wsl.yml tests/python/test_ci_workflow_routing.py scripts/powershell/tests/CiWorkflow.Tests.ps1
git commit -m "ci: gate Linux and WSL bootstrap checks by platform"
```

### Task 9: Remove Duplicate Chezmoi Pester Execution

**Files:**

- Modify: .github/workflows/ci-chezmoi.yml
- Modify: scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1
- Modify: scripts/powershell/tests/CiWorkflow.Tests.ps1
- Modify: tests/python/test_ci_workflow_routing.py

**Interfaces:**

- lint remains Lint (Pester chezmoi) and is the only job running tests/chezmoi.
- fmt and op-guard retain their required names.
- JUnit output moves to lint; duplicate test job is removed.

- [ ] **Step 1: Write failing deduplication assertions**

Assert exactly one tests/chezmoi occurrence, no top-level test job, all three required names, and JUnit artifact upload from lint.

- [ ] **Step 2: Verify RED**

```bash
python3 -m unittest tests/python/test_ci_workflow_routing.py -v
```

- [ ] **Step 3: Remove the duplicate job**

Call Invoke-Tests.ps1 from lint with -OutputFile chezmoi-test-results.xml. Upload scripts/powershell/chezmoi-test-results.xml with always(). Delete test without renaming required jobs.

- [ ] **Step 4: Update PowerShell contracts**

Remove the Chezmoi test-job case from Keybindings.Tests.ps1. Replace CiWorkflow assertions for needs: [lint, fmt, font-install] with one-Pester-invocation and required-name assertions.

- [ ] **Step 5: Verify GREEN and commit**

```bash
python3 -m unittest tests/python/test_ci_workflow_routing.py -v
pwsh -NoProfile -Command '& ./scripts/powershell/tests/Invoke-Tests.ps1 -Path @("./scripts/powershell/tests/CiWorkflow.Tests.ps1", "./scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1") -MinimumCoverage 0'
go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12 .github/workflows/ci-chezmoi.yml
git add .github/workflows/ci-chezmoi.yml scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1 scripts/powershell/tests/CiWorkflow.Tests.ps1 tests/python/test_ci_workflow_routing.py
git commit -m "ci: remove duplicate Chezmoi Pester job"
```

### Task 10: Full Verification and Diff Review

**Files:**

- Verify all files changed by Tasks 1-9.

- [ ] **Step 1: Run all automated contracts**

```bash
python3 -m unittest discover -s tests/python -v
bats --print-output-on-failure tests/bash
pwsh -NoProfile -Command '& ./scripts/powershell/tests/Invoke-Tests.ps1 -Path @("./scripts/powershell/tests/CiWorkflow.Tests.ps1", "./scripts/powershell/tests/PackageCatalog.Tests.ps1", "./scripts/powershell/tests/HermesBootstrapEntrypoint.Tests.ps1", "./scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1") -MinimumCoverage 0'
go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12
```

- [ ] **Step 2: Run focused formatting**

```bash
nix fmt -- \
  ci/path-routing.json \
  scripts/python/detect_ci_changes.py \
  tests/python/test_detect_ci_changes.py \
  tests/python/test_detect_ci_action_contract.py \
  tests/python/test_ci_workflow_routing.py \
  tests/bash/ci_routing.bats \
  .github/actions/detect-ci-changes/action.yml \
  .github/workflows/ci-contract.yml \
  .github/workflows/ci-nix.yml \
  .github/workflows/ci-devcontainer.yml \
  .github/workflows/ci-hermes-bootstrap.yml \
  .github/workflows/ci-bootstrap-build.yml \
  .github/workflows/ci-bootstrap-e2e-hosted.yml \
  .github/workflows/ci-bootstrap-e2e-linux.yml \
  .github/workflows/ci-nixos-wsl.yml \
  .github/workflows/ci-chezmoi.yml \
  .pre-commit-config.yaml \
  taskfiles/hermes/taskfile.yml \
  scripts/powershell/tests/CiWorkflow.Tests.ps1 \
  scripts/powershell/tests/chezmoi/Keybindings.Tests.ps1
```

- [ ] **Step 3: Re-run Step 1 after formatting**

Expected: zero failures in Python, Bats, Pester, and actionlint.

- [ ] **Step 4: Review scope and acceptance criteria**

```bash
git status --short
git diff --check main...HEAD
git diff --stat main...HEAD
git diff main...HEAD -- .github ci scripts/python tests taskfiles .pre-commit-config.yaml docs/superpowers
```

Confirm all four platform outputs have tests, required Chezmoi names remain, aggregate jobs accept skipped but reject failure, and no installer/package/user configuration behavior changed.

- [ ] **Step 5: Commit formatting-only changes if present**

```bash
git add --update
git commit -m "style: format CI routing changes"
```

Skip the commit when formatting produced no diff.
