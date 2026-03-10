# Sandbox Git-Native Workflow Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable sandbox containers to clone repos, install deps with cached package managers, and create PRs autonomously.

**Architecture:** Replace the inline `printf | docker build` sandbox build step with a proper `Dockerfile.sandbox-custom` that adds uv, gh CLI (static binary), and Playwright. Add `binds` to OpenClaw config for package cache persistence. Update Taskfile tasks accordingly.

**Tech Stack:** Docker, Taskfile (go-task), chezmoi templates, shell

---

## File Structure

| File                                             | Action | Responsibility                                                             |
| ------------------------------------------------ | ------ | -------------------------------------------------------------------------- |
| `docker/openclaw/Dockerfile.sandbox-custom`      | Create | Custom sandbox image layer (uv, gh CLI, Playwright, git config)            |
| `Taskfile.yml`                                   | Modify | Update `sandbox:build`, add `sandbox:cache-init` and `sandbox:cache-clean` |
| `chezmoi/dot_openclaw/openclaw.docker.json.tmpl` | Modify | Add `binds` field for package cache mounts                                 |
| `docs/chezmoi/dot_openclaw/04-sandbox.md`        | Modify | Document binds configuration and git-native workflow                       |

---

## Chunk 1: Dockerfile and Image Build

### Task 1: Create Dockerfile.sandbox-custom

**Files:**

- Create: `docker/openclaw/Dockerfile.sandbox-custom`

- [ ] **Step 1: Create the Dockerfile**

```dockerfile
# syntax=docker/dockerfile:1
ARG SBX_COMMON_BASE=openclaw-sandbox-common:bookworm-slim-base

# ── Tool sources ──
FROM docker:27-cli AS docker-cli
FROM ghcr.io/astral-sh/uv:0.6 AS uv-bin

# ── Main image ──
FROM ${SBX_COMMON_BASE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Docker CLI (sibling container management)
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker

# uv (Python package manager) - COPY --from is fastest
COPY --from=uv-bin /uv /uvx /usr/local/bin/

# Python via uv (consistent version management)
ARG PYTHON_VERSION=3.12
RUN uv python install ${PYTHON_VERSION}

# gh CLI (static binary from GitHub Releases)
ARG GH_VERSION=2.86.0
RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
    | tar xz --strip-components=2 -C /usr/local/bin "gh_${GH_VERSION}_linux_amd64/bin/gh"

# Playwright (Chromium only)
# Browser binaries are installed at build time into PLAYWRIGHT_BROWSERS_PATH.
# Runtime writes (profiles, temp) go to /tmp (covered by tmpfs).
ENV PLAYWRIGHT_BROWSERS_PATH=/root/.cache/ms-playwright
RUN npx -y playwright install --with-deps chromium

# Git defaults for sandbox operations
# safe.directory "*" is intentionally permissive - sandbox containers are
# ephemeral and isolated, so directory trust is not a meaningful security boundary.
RUN git config --global user.name "openclaw" \
    && git config --global user.email "openclaw@sandbox" \
    && git config --global safe.directory "*" \
    && git config --global init.defaultBranch main
```

- [ ] **Step 2: Verify Dockerfile syntax with hadolint**

Run: `docker run --rm -i hadolint/hadolint < docker/openclaw/Dockerfile.sandbox-custom`
Expected: No errors (warnings about unpinned versions are acceptable for upstream-dependent images)

- [ ] **Step 3: Commit**

```bash
git add docker/openclaw/Dockerfile.sandbox-custom
git commit -m "feat(sandbox): add Dockerfile.sandbox-custom with uv, gh CLI, Playwright"
```

### Task 2: Update sandbox:build in Taskfile.yml

**Files:**

- Modify: `Taskfile.yml:122-150`

- [ ] **Step 1: Update the sandbox:build task**

Replace the entire `sandbox:build` task block in `Taskfile.yml` (search for `sandbox:build:` through to the next task `sandbox:ps:`). The key changes:

1. Add `SBX_COMMON_BASE` variable for intermediate image tag
2. Change step 2 to tag intermediate as `-base` (using new variable)
3. Replace the inline `printf | docker build` step 3 with `docker build -f Dockerfile.sandbox-custom`

```yaml
sandbox:build:
  desc: Build sandbox Docker images from OpenClaw upstream + custom layer
  vars:
    SBX_BASE: openclaw-sandbox:bookworm-slim
    SBX_COMMON_BASE: openclaw-sandbox-common:bookworm-slim-base
    SBX_COMMON: openclaw-sandbox-common:bookworm-slim
    SBX_REPO: https://raw.githubusercontent.com/openclaw/openclaw/main
    BUILD_DIR: '{{.TEMP | default "/tmp"}}/openclaw-sandbox-build'
  cmds:
    - cmd: mkdir -p "{{.BUILD_DIR}}"
    - cmd: curl -fsSL "{{.SBX_REPO}}/Dockerfile.sandbox" -o "{{.BUILD_DIR}}/Dockerfile.sandbox"
    - cmd: curl -fsSL "{{.SBX_REPO}}/Dockerfile.sandbox-common" -o "{{.BUILD_DIR}}/Dockerfile.sandbox-common"
    - cmd: >-
        docker build -t "{{.SBX_BASE}}"
        -f "{{.BUILD_DIR}}/Dockerfile.sandbox"
        "{{.BUILD_DIR}}/"
    - cmd: >-
        docker build -t "{{.SBX_COMMON_BASE}}"
        --build-arg BASE_IMAGE={{.SBX_BASE}}
        --build-arg "PACKAGES=curl wget jq coreutils grep nodejs npm python3 git ca-certificates unzip"
        --build-arg INSTALL_PNPM=1
        --build-arg INSTALL_BUN=1
        --build-arg INSTALL_BREW=0
        --build-arg FINAL_USER=root
        -f "{{.BUILD_DIR}}/Dockerfile.sandbox-common"
        "{{.BUILD_DIR}}/"
    # Custom layer: uv, gh CLI, Playwright, git config
    - cmd: >-
        docker build -t "{{.SBX_COMMON}}"
        --build-arg SBX_COMMON_BASE={{.SBX_COMMON_BASE}}
        -f docker/openclaw/Dockerfile.sandbox-custom
        docker/openclaw/
```

- [ ] **Step 2: Verify task definition parses correctly**

Run: `task sandbox:build --dry`
Expected: Shows the commands that would run without errors. The `--dry` flag prints commands without executing.

- [ ] **Step 3: Commit**

```bash
git add Taskfile.yml
git commit -m "refactor(sandbox): replace inline Dockerfile with Dockerfile.sandbox-custom in sandbox:build"
```

### Task 3: Add cache management tasks to Taskfile.yml

**Files:**

- Modify: `Taskfile.yml` (add after `sandbox:gc` task, around line 191)

- [ ] **Step 1: Add sandbox:cache-init and sandbox:cache-clean tasks**

Insert before the `# Windows Setup` comment separator in `Taskfile.yml` (after the `sandbox:gc` task block):

```yaml
sandbox:cache-init:
  desc: Initialize sandbox cache directories on gateway
  preconditions:
    - sh: docker ps -q -f name=^openclaw$ | grep -q .
      msg: "Gateway container 'openclaw' is not running. Start it first."
  cmds:
    - docker exec openclaw mkdir -p
      /app/data/workspace/.cache/uv
      /app/data/workspace/.cache/pnpm
      /app/data/workspace/.cache/bun
      /app/data/workspace/.cache/npm

sandbox:cache-clean:
  desc: Remove all sandbox package caches
  prompt: This will delete all cached packages. Continue?
  cmds:
    - docker exec openclaw rm -rf
      /app/data/workspace/.cache/uv
      /app/data/workspace/.cache/pnpm
      /app/data/workspace/.cache/bun
      /app/data/workspace/.cache/npm
    - task: sandbox:cache-init
```

- [ ] **Step 2: Verify task definitions parse**

Run: `task --list | grep -E "sandbox:cache"`
Expected:

```
* sandbox:cache-clean:    Remove all sandbox package caches
* sandbox:cache-init:     Initialize sandbox cache directories on gateway
```

- [ ] **Step 3: Commit**

```bash
git add Taskfile.yml
git commit -m "feat(sandbox): add cache-init and cache-clean tasks for package manager caches"
```

## Chunk 2: OpenClaw Config and Documentation

### Task 4: Add binds to openclaw.docker.json.tmpl

**Files:**

- Modify: `chezmoi/dot_openclaw/openclaw.docker.json.tmpl:57-86`

- [ ] **Step 1: Add binds field to sandbox.docker section**

In `chezmoi/dot_openclaw/openclaw.docker.json.tmpl`, add the `binds` array after the `capDrop` line (line 68) and before `pidsLimit` (line 69):

```jsonc
          "capDrop": ["ALL"],
          "binds": [
            "/app/data/workspace/.cache/uv:/root/.cache/uv:rw",
            "/app/data/workspace/.cache/pnpm:/root/.local/share/pnpm/store:rw",
            "/app/data/workspace/.cache/bun:/root/.bun/install/cache:rw",
            "/app/data/workspace/.cache/npm:/root/.npm:rw"
          ],
          "pidsLimit": {{ .openclaw.sandbox.pidsLimit }},
```

- [ ] **Step 2: Verify template syntax visually**

Visual check: Ensure the `binds` array has proper JSON syntax — matching brackets, trailing commas after each entry except the last, double quotes on all strings. The template contains Go/chezmoi directives (`{{ }}`, `{{- if }}`) so standard JSON parsers will reject it; visual inspection is sufficient.

- [ ] **Step 3: Commit**

```bash
git add chezmoi/dot_openclaw/openclaw.docker.json.tmpl
git commit -m "feat(sandbox): add binds for package manager cache persistence"
```

### Task 5: Update sandbox documentation

**Files:**

- Modify: `docs/chezmoi/dot_openclaw/04-sandbox.md`

- [ ] **Step 1: Add binds documentation after the セキュリティ設定 section**

In `docs/chezmoi/dot_openclaw/04-sandbox.md`, insert a new `### Bind マウント（パッケージキャッシュ）` subsection after the `> **注**:` block (after line 57) and before the `### リソース制限` section (line 59). Add the following markdown:

```markdown
### Bind マウント（パッケージキャッシュ）

sandbox コンテナにパッケージマネージャのキャッシュを bind mount で永続化する。`readOnlyRoot: true` との共存は問題ない（bind mount は独立したマウントポイントのため、read-only root filesystem の影響を受けない）。

| Gateway パス                      | sandbox パス                    | 用途                           |
| --------------------------------- | ------------------------------- | ------------------------------ |
| `/app/data/workspace/.cache/uv`   | `/root/.cache/uv`               | uv パッケージキャッシュ        |
| `/app/data/workspace/.cache/pnpm` | `/root/.local/share/pnpm/store` | pnpm content-addressable store |
| `/app/data/workspace/.cache/bun`  | `/root/.bun/install/cache`      | bun パッケージキャッシュ       |
| `/app/data/workspace/.cache/npm`  | `/root/.npm`                    | npm キャッシュ                 |

キャッシュ管理:

- 初期化: `task sandbox:cache-init`（gateway コンテナ実行中に実行）
- クリーンアップ: `task sandbox:cache-clean`（全キャッシュ削除後に再初期化）
```

- [ ] **Step 2: Add git-native workflow documentation**

In the same file, insert a new `## Git-Native ワークフロー` section before the `## 設計判断` section (before line 112). Add the following markdown:

```markdown
## Git-Native ワークフロー

sandbox 内でリポジトリの clone → 編集 → commit → push → PR 作成まで完結させる。PR をセーフティゲートとして利用する。

### フロー

1. `git clone --depth=1 https://github.com/<user>/<repo>.git`
2. ファイル編集、`uv sync` / `pnpm install` で依存インストール（キャッシュヒットで高速）
3. `git commit` → `git push` → `gh pr create`

### 認証

既存の環境変数で自動設定済み:

- `GITHUB_TOKEN` / `GH_TOKEN`: GitHub API / gh CLI 認証
- `GIT_CONFIG_*`: `https://github.com/` を token 付き URL に自動書き換え（insteadOf 方式）

追加設定は不要。fine-grained PAT で対象リポジトリを制限済み。
```

- [ ] **Step 3: Commit**

```bash
git add docs/chezmoi/dot_openclaw/04-sandbox.md
git commit -m "docs(sandbox): document binds configuration and git-native workflow"
```

### Task 6: Build and verify the image (E2E)

This task requires Docker Desktop running and network access.

- [ ] **Step 1: Build the sandbox image**

Run: `task sandbox:build`
Expected: All 3 stages complete successfully. Final image tagged as `openclaw-sandbox-common:bookworm-slim`.

- [ ] **Step 2: Verify tools are installed in the image**

Run:

```bash
docker run --rm openclaw-sandbox-common:bookworm-slim bash -c "
  echo '=== uv ===' && uv --version &&
  echo '=== gh ===' && gh --version &&
  echo '=== docker ===' && docker --version &&
  echo '=== python ===' && python3 --version &&
  echo '=== pnpm ===' && pnpm --version &&
  echo '=== bun ===' && bun --version &&
  echo '=== git ===' && git --version &&
  echo '=== playwright ===' && npx playwright --version
"
```

Expected: All tools report their versions without error.

- [ ] **Step 3: Verify git config**

Run:

```bash
docker run --rm openclaw-sandbox-common:bookworm-slim bash -c "
  git config --global user.name &&
  git config --global user.email &&
  git config --global init.defaultBranch &&
  git config --global safe.directory
"
```

Expected:

```
openclaw
openclaw@sandbox
main
*
```

- [ ] **Step 4: Verify image size**

Run: `docker images openclaw-sandbox-common:bookworm-slim --format "{{.Size}}"`
Expected: Around 1.1GB (acceptable range: 800MB - 1.5GB)

- [ ] **Step 5: Initialize caches and verify binds work**

Run (requires gateway container running):

```bash
task sandbox:cache-init
docker exec openclaw ls -la /app/data/workspace/.cache/
```

Expected: Directories `uv`, `pnpm`, `bun`, `npm` exist under `/app/data/workspace/.cache/`.

- [ ] **Step 6: Apply chezmoi and restart gateway**

Run:

```bash
chezmoi apply --source D:/dotfiles/chezmoi
docker restart openclaw
```

Verify sandbox config includes binds:
Run: `task sandbox:explain | grep -A5 binds`
Expected: Shows the 4 bind mount entries.

- [ ] **Step 7: Commit (if any adjustments were needed)**

Only commit if changes were made during verification. Skip if no changes needed.

```bash
git add docker/openclaw/Dockerfile.sandbox-custom Taskfile.yml chezmoi/dot_openclaw/openclaw.docker.json.tmpl docs/chezmoi/dot_openclaw/04-sandbox.md
git commit -m "fix(sandbox): adjustments from E2E verification"
```
