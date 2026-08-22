# Unified Bootstrap CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 統合した `Bootstrap CI` で Linux、Darwin、WSL、Windows の bootstrap 検証を並列実行し、変更 path に応じて対象 platform だけを起動する。

**Architecture:** 通常 CI 用の `ci/path-routing.json` は維持し、bootstrap 専用の `ci/bootstrap-path-routing.json` を追加する。composite action に manifest path の入力を追加し、統合 workflow の一つの `changes` job が bootstrap manifest を使って platform outputs を生成する。OS ごとの runner/shell/手順差が大きいため、単一 matrix step ではなく、共通 `changes` の後に platform 別 job 群を相互依存なしで起動する。

**Tech Stack:** GitHub Actions YAML、composite action、Python 3.14、Bats、PowerShell/Pester、既存の Nix/Docker/WSL E2E scripts

**Spec:** `docs/superpowers/specs/2026-08-22-bootstrap-ci-design.md`

## Global Constraints

- Workflow 名は `Bootstrap CI`、集約 job 名は `Bootstrap / Complete` とする。
- Build、Contract、E2E を検証層の語彙として使用し、旧 workflow 名を新 workflow に残さない。
- Linux、Darwin、WSL、Windows の platform outputs は job-level `if` で個別評価する。
- WSL 専用 bootstrap path は WSL output のみを有効化し、Windows bootstrap contract を起動しない。
- 共有 path と `workflow_dispatch` は必要な全 platform を実行する。
- 既存 `ci/path-routing.json` の通常 CI 向け WSL/Windows 連動契約は変更しない。
- fork pull request の Windows/WSL privileged runtime 保護を維持する。
- 既存の bootstrap test command、runner、timeout、attestation、artifact 内容を必要なく変更しない。

---

### Task 1: Bootstrap routing の failing contract を追加する

**Files:**

- Create: `ci/bootstrap-path-routing.json`
- Modify: `tests/python/test_detect_ci_changes.py`
- Modify: `tests/bash/ci_routing.bats`

**Interfaces:**

- Consumes: 既存の `scripts/python/detect_ci_changes.py --manifest` API
- Produces: bootstrap manifest に対する platform routing の期待値

- [ ] **Step 1: Write the failing tests**

`tests/python/test_detect_ci_changes.py` に bootstrap manifest path と次のケースを追加する。

```python
BOOTSTRAP_CASES = {
    "windows/winget/packages.json": {"windows", "contract"},
    "nix/darwin/default.nix": {"darwin", "contract"},
    "nix/hosts/linux/configuration.nix": {"linux", "contract"},
    "nix/hosts/wsl/configuration.nix": {"wsl", "contract"},
    "scripts/powershell/handlers/Handler.NixOSWSL.ps1": {"wsl", "contract"},
    "scripts/powershell/lib/SetupHandler.ps1": {"wsl", "windows", "contract"},
    "nix/packages/sets.nix": {
        "linux", "darwin", "wsl", "windows", "contract",
    },
}

def test_bootstrap_paths_route_only_their_platform(self) -> None:
    for path, expected_enabled in BOOTSTRAP_CASES.items():
        with self.subTest(path=path):
            result = self.detector.route_paths([path], BOOTSTRAP_MANIFEST_PATH)
            self.assertEqual(
                {name for name, enabled in result.items() if enabled},
                expected_enabled,
            )
```

`tests/bash/ci_routing.bats` に bootstrap manifest を直接呼び出す Linux、Darwin、WSL、Windows、共有 path のケースを追加する。

- [ ] **Step 2: Run the focused tests and verify they fail**

```bash
python3 -m unittest tests/python/test_detect_ci_changes.py -v
bats tests/bash/ci_routing.bats
```

Expected: bootstrap manifest が存在しないため、新しい routing ケースが失敗する。

- [ ] **Step 3: Write the minimal bootstrap manifest**

`ci/bootstrap-path-routing.json` は既存 detector schema の全 output 名を保持する。rules は bootstrap の platform routing に限定し、`contract` は detector の既存 default に任せる。少なくとも次の分類を含める。

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
  "rules": [
    { "patterns": ["windows/**", "install.cmd"], "outputs": ["windows"] },
    { "patterns": ["nix/darwin/**", "scripts/sh/install-macos.sh"], "outputs": ["darwin"] },
    {
      "patterns": [
        "nix/home/linux/**",
        "nix/hosts/linux/**",
        "nix/system-manager/**",
        "nix/tests/**",
        "scripts/sh/install-linux.sh",
        "scripts/sh/install-nixos.sh",
        ".github/e2e/**"
      ],
      "outputs": ["linux"]
    },
    {
      "patterns": [
        "nix/home/wsl/**",
        "nix/hosts/wsl/**",
        "nix/modules/wsl/**",
        "scripts/sh/nixos-wsl-postinstall.sh",
        "scripts/powershell/ci/Invoke-NixosWslE2E.ps1",
        "scripts/powershell/handlers/Handler.NixOSWSL.ps1"
      ],
      "outputs": ["wsl"]
    },
    { "patterns": ["scripts/powershell/lib/**"], "outputs": ["wsl", "windows"] },
    {
      "patterns": [
        "nix/packages/**",
        "scripts/sh/install-common.sh",
        "docker/hermes-agent/**",
        "docker/hermes-browser/**",
        "docker/hermes-browser-mcp/**",
        "docker/hermes-xapi-mcp/**",
        "Taskfile.yml"
      ],
      "outputs": ["linux", "darwin", "wsl", "windows"]
    }
  ]
}
```

Expand the patterns with all existing bootstrap trigger paths, including routing infrastructure, common chezmoi paths, Home Manager paths, and the new workflow path. Do not add a broad `scripts/powershell/**` rule because it would make WSL-specific handler changes select Windows.

- [ ] **Step 4: Run the focused tests and verify they pass**

```bash
python3 -m unittest tests/python/test_detect_ci_changes.py -v
bats tests/bash/ci_routing.bats
```

- [ ] **Step 5: Commit the routing contract**

```bash
git add ci/bootstrap-path-routing.json tests/python/test_detect_ci_changes.py tests/bash/ci_routing.bats
git commit -m "test: define bootstrap platform routing"
```

### Task 2: Make the detector action consume a selected manifest

**Files:**

- Modify: `.github/actions/detect-ci-changes/action.yml`
- Modify: `.github/workflows/ci-contract.yml`
- Modify: `tests/python/test_ci_workflow_routing.py`

**Interfaces:**

- Consumes: optional action input `manifest`, defaulting to `ci/path-routing.json`
- Produces: the same fixed action outputs, populated from the selected manifest

- [ ] **Step 1: Write the failing workflow contract**

Assert that the action declares `manifest`, defaults to `ci/path-routing.json`, and passes the selected value as `--manifest` in both the `--all` and changed-path branches. Add `ci/bootstrap-path-routing.json` to the always-run path list of `ci-contract.yml`.

- [ ] **Step 2: Run the focused contract test and verify it fails**

```bash
python3 -m unittest tests/python/test_ci_workflow_routing.py -v
```

Expected: the new action manifest assertions fail because the input is not present.

- [ ] **Step 3: Implement the action input**

Add this input to `.github/actions/detect-ci-changes/action.yml`:

```text
  manifest:
    description: Routing manifest path relative to the repository root.
    required: false
    default: ci/path-routing.json
```

Expose it as `MANIFEST_PATH` in the detection step and add `--manifest "${MANIFEST_PATH}"` before `--all` or `--paths-file` in both detector invocations.

- [ ] **Step 4: Run the focused contract test and verify it passes**

```bash
python3 -m unittest tests/python/test_ci_workflow_routing.py -v
```

- [ ] **Step 5: Commit the action interface**

```bash
git add .github/actions/detect-ci-changes/action.yml .github/workflows/ci-contract.yml tests/python/test_ci_workflow_routing.py
git commit -m "ci: allow workflows to select a routing manifest"
```

### Task 3: Add the unified Bootstrap CI workflow

**Files:**

- Create: `.github/workflows/ci-bootstrap.yml`
- Delete: `.github/workflows/ci-bootstrap-build.yml`
- Delete: `.github/workflows/ci-bootstrap-e2e-linux.yml`
- Delete: `.github/workflows/ci-bootstrap-e2e-hosted.yml`
- Delete: `.github/workflows/ci-nixos-wsl.yml`

**Interfaces:**

- Consumes: `changes` outputs from `ci/bootstrap-path-routing.json`
- Produces: `Bootstrap / Linux / *`, `Bootstrap / Darwin / *`, `Bootstrap / WSL`, `Bootstrap / Windows`, and `Bootstrap / Complete` jobs

- [ ] **Step 1: Write the failing workflow contract**

Update `tests/python/test_ci_workflow_routing.py` and `scripts/powershell/tests/CiWorkflow.Tests.ps1` to inspect `.github/workflows/ci-bootstrap.yml`, assert `name: Bootstrap CI`, all four detector outputs, the new display names, the selected manifest, the aggregate result guard, the existing platform commands, and fork protection. Remove assertions whose only purpose is to require deleted workflow files.

- [ ] **Step 2: Run the workflow contract and verify it fails**

```bash
python3 -m unittest tests/python/test_ci_workflow_routing.py -v
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -MinimumCoverage 0
```

Expected: the new workflow contract fails because the unified workflow does not exist.

- [ ] **Step 3: Implement the unified workflow**

Create `.github/workflows/ci-bootstrap.yml` with the union of the existing bootstrap path filters plus the bootstrap manifest, detector action, detector tests, `ci-contract.yml`, and the new workflow itself.

The `changes` job must expose `linux`, `darwin`, `wsl`, and `windows`, pass `manifest: ci/bootstrap-path-routing.json`, and preserve the existing base/head SHA expressions and `run-all` behavior.

Create independent jobs for the existing Linux build, Ubuntu destructive E2E, Debian systemd E2E, and NixOS VM build. Add Darwin, WSL, and Windows jobs with the existing commands, runner setup, fork protection, attestation, JUnit, and artifact behavior. Every job must require `changes` and its own platform output. Use display names `Bootstrap / Darwin`, `Bootstrap / WSL`, and `Bootstrap / Windows`; name Linux jobs `Bootstrap / Linux / Build` or `Bootstrap / Linux / E2E / <target>`.

Add `Bootstrap / Complete` with `if: always()`, needs covering `changes` and every platform job, and a shell guard that accepts only `success|skipped` for each result. Give artifacts unique names containing platform, layer, `github.run_id`, and `github.run_attempt`.

- [ ] **Step 4: Run the workflow contract and verify it passes**

```bash
python3 -m unittest tests/python/test_ci_workflow_routing.py -v
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -MinimumCoverage 0
```

- [ ] **Step 5: Commit the unified workflow**

```bash
git add .github/workflows/ci-bootstrap.yml .github/workflows/ci-bootstrap-build.yml .github/workflows/ci-bootstrap-e2e-linux.yml .github/workflows/ci-bootstrap-e2e-hosted.yml .github/workflows/ci-nixos-wsl.yml tests/python/test_ci_workflow_routing.py scripts/powershell/tests/CiWorkflow.Tests.ps1
git commit -m "ci: unify platform bootstrap workflows"
```

### Task 4: Validate routing, syntax, and final scope

**Files:**

- Modify only if required by focused validation: bootstrap manifest, unified workflow, routing/action tests

**Interfaces:**

- Consumes: completed unified workflow and both routing manifests
- Produces: verified diff with no stale executable references

- [ ] **Step 1: Run focused routing and workflow tests**

```bash
python3 -m unittest tests/python/test_detect_ci_changes.py tests/python/test_ci_workflow_routing.py -v
bats tests/bash/ci_routing.bats
pwsh -NoProfile -File scripts/powershell/tests/Invoke-Tests.ps1 -MinimumCoverage 0
```

- [ ] **Step 2: Run YAML/action syntax validation**

```bash
go run github.com/rhysd/actionlint/cmd/actionlint@v1.7.12 .github/workflows/ci-bootstrap.yml .github/workflows/ci-contract.yml
```

- [ ] **Step 3: Verify stale references and the route matrix**

```bash
rg -n "ci-bootstrap-build|ci-bootstrap-e2e-linux|ci-bootstrap-e2e-hosted|ci-nixos-wsl" .github tests scripts ci
python3 scripts/python/detect_ci_changes.py --manifest ci/bootstrap-path-routing.json --paths-file <(printf '%s\n' windows/winget/packages.json)
python3 scripts/python/detect_ci_changes.py --manifest ci/bootstrap-path-routing.json --paths-file <(printf '%s\n' nix/darwin/default.nix)
python3 scripts/python/detect_ci_changes.py --manifest ci/bootstrap-path-routing.json --paths-file <(printf '%s\n' nix/hosts/wsl/configuration.nix)
```

Expected: Windows, Darwin, and WSL examples select only their respective bootstrap platform plus the default contract output; only intentional spec/plan references remain for old names.

- [ ] **Step 4: Review the final diff and status**

```bash
git diff --check
git diff --stat
git status --short --branch
```

Confirm unrelated files are untouched, exactly one bootstrap workflow remains, and global routing behavior was not accidentally changed.

- [ ] **Step 5: Commit any validation-only correction**

```bash
git add ci/bootstrap-path-routing.json .github/workflows/ci-bootstrap.yml tests/python/test_detect_ci_changes.py tests/python/test_ci_workflow_routing.py tests/bash/ci_routing.bats scripts/powershell/tests/CiWorkflow.Tests.ps1
git commit -m "test: verify unified bootstrap routing"
```
