# Sandbox Git-Native Workflow Design

## Summary

OpenClaw sandbox を Git-native ワークフローに移行する。sandbox 内でリポジトリの clone → 編集 → commit → push → PR 作成まで完結させ、PR をセーフティゲートとする。パッケージマネージャのキャッシュを bind mount で永続化し、毎セッションの install コストを最小化する。

## 背景

現状の sandbox は `/workspace` に gateway の workspace volume がマウントされ、ファイル編集はできるが git 操作やデータ永続化の設計が不明確。sandbox から lifelog 等の永続データに書き込む場合、保存先が不明で詰まる問題が報告された。

## 設計方針

### Git-Native（sandbox 完結型）

```
Sandbox: git clone → edit → uv sync/pnpm install → commit → push → PR
Human: レビュー → マージ
```

- PR 自体がセーフティゲート。reject すれば何も起きない
- Devin、GitHub Copilot Workspace、Codex と同じモデル
- fine-grained PAT で対象リポジトリを制限済み
- sandbox の ephemeral 性と相性がいい（毎回クリーンな状態）

### 単一 Fat Image（全パッケージマネージャ入り）

リポジトリ側に Dockerfile を置かない。sandbox に全ツールを入れ、リポジトリには `pyproject.toml` / `package.json` のみを置く。

### Named Volume ではなく binds

OpenClaw 2026.3.x は sandbox に named volume をサポートしていない。`binds` フィールドで bind mount を使用する。

## 移行内容

現在の `Taskfile.yml` にある inline `printf ... | docker build` コマンド（Docker CLI + gh CLI + Playwright をレイヤリング）を、正式な `Dockerfile.sandbox-custom` に置き換える。

主な変更点:

- gh CLI: apt リポジトリ経由 → GitHub Releases 静的バイナリ（GPG キー管理不要、軽量化）
- uv: 新規追加（`COPY --from` パターン）
- Python: upstream の apt python3 に加え、uv 管理の Python を追加（uv が優先的に使用。apt python3 は upstream 依存のため残るが、`uv run` / `uv sync` は uv 管理の Python を使う）
- `init.defaultBranch main`: 新規追加（Git-native ワークフローで必要）

## アーキテクチャ

### イメージレイヤー構成

```
Upstream base (Dockerfile.sandbox: bookworm-slim)
  └─ Upstream common (Dockerfile.sandbox-common: nodejs, python3, git, pnpm, bun)
      └─ Custom layer (Dockerfile.sandbox-custom: uv, gh CLI, Playwright, git config)
```

### Dockerfile.sandbox-custom

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

### イメージサイズ見積もり

| レイヤー                                          | サイズ     |
| ------------------------------------------------- | ---------- |
| upstream base (bookworm-slim)                     | ~80MB      |
| upstream common (nodejs, python3, git, pnpm, bun) | ~500MB     |
| Docker CLI                                        | ~50MB      |
| uv                                                | ~30MB      |
| Python 3.12 (uv)                                  | ~100MB     |
| gh CLI                                            | ~50MB      |
| Playwright + Chromium                             | ~400MB     |
| **合計**                                          | **~1.1GB** |

## キャッシュ戦略

### bind mount によるパッケージキャッシュ永続化

Gateway コンテナの `/app/data/` 配下にキャッシュディレクトリを作成し、sandbox に bind mount する。

```jsonc
// openclaw.docker.json sandbox.docker セクション
"binds": [
  "/app/data/workspace/.cache/uv:/root/.cache/uv:rw",
  "/app/data/workspace/.cache/pnpm:/root/.local/share/pnpm/store:rw",
  "/app/data/workspace/.cache/bun:/root/.bun/install/cache:rw",
  "/app/data/workspace/.cache/npm:/root/.npm:rw"
]
```

キャッシュサイズは手動管理で十分。肥大化した場合は `sandbox:cache-clean` タスクで削除（Taskfile セクション参照）。

### 効果

| 操作                  | 初回               | 2回目以降               |
| --------------------- | ------------------ | ----------------------- |
| `uv sync` (PyTorch等) | 数分 (DL)          | 数秒 (キャッシュヒット) |
| `pnpm install`        | 数十秒             | 数秒 (store 再利用)     |
| `bun install`         | 数十秒             | 数秒                    |
| `git clone`           | `--depth=1` で高速 | 同じ（Phase 1）         |

### repo-cache の運用

repo-cache は将来の最適化として扱う。Phase 1 では sandbox は毎回 `git clone --depth=1` する（dotfiles 等の小規模リポジトリでは十分高速）。大規模リポジトリで clone コストが問題になった場合に以下を導入する:

- Gateway の `/app/data/workspace/.cache/repos/` に bare clone を保持
- `sandbox:cache-repos` タスクで手動更新、または Gateway の cron で定期 `git fetch`
- sandbox 起動時: `git clone --reference /workspace/.repo-cache/<repo>.git --depth=1`
- キャッシュ対象リポジトリは Taskfile の変数で管理

## OpenClaw 設定変更

### openclaw.docker.json.tmpl

既存の `sandbox.docker` セクションに `binds` フィールドを**新規追加**する。`readOnlyRoot: true` との共存は問題ない（bind mount は独立したマウントポイントのため、read-only root filesystem の影響を受けない）。

認証は既存の `env` セクションで設定済み（`GITHUB_TOKEN`, `GH_TOKEN`, `GIT_CONFIG_*` による HTTPS token auth URL rewriting）。追加設定不要。

```jsonc
"sandbox": {
  "sessionToolsVisibility": "all",
  "mode": "all",
  "scope": "session",
  "workspaceAccess": "rw",
  "docker": {
    "image": "openclaw-sandbox-common:bookworm-slim",
    "network": "bridge",
    "user": "0:0",
    "readOnlyRoot": true,
    "tmpfs": ["/tmp", "/var/tmp", "/run"],
    "capDrop": ["ALL"],
    "binds": [
      "/app/data/workspace/.cache/uv:/root/.cache/uv:rw",
      "/app/data/workspace/.cache/pnpm:/root/.local/share/pnpm/store:rw",
      "/app/data/workspace/.cache/bun:/root/.bun/install/cache:rw",
      "/app/data/workspace/.cache/npm:/root/.npm:rw"
    ],
    // 既存の env, resource limits は変更なし
    // repo-cache の binds は将来の最適化時に追加
  }
}
```

## ファイル配置

| ファイル                                         | 説明                                                                          |
| ------------------------------------------------ | ----------------------------------------------------------------------------- |
| `docker/openclaw/Dockerfile.sandbox-custom`      | 新規: カスタムレイヤー Dockerfile                                             |
| `chezmoi/dot_openclaw/openclaw.docker.json.tmpl` | 変更: `binds` フィールド追加                                                  |
| `Taskfile.yml`                                   | 変更: `sandbox:build` 更新、`sandbox:cache-init` / `sandbox:cache-clean` 追加 |

## Taskfile 変更

### sandbox:build タスクの更新

既存の inline `printf ... | docker build` ステップ（Taskfile.yml 148-150行目）を `Dockerfile.sandbox-custom` に置き換える。変数 `SBX_COMMON_BASE` を新規追加し、中間イメージと最終イメージを明確に分離する。

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
    # 1. Upstream base
    - cmd: mkdir -p "{{.BUILD_DIR}}"
    - cmd: curl -fsSL "{{.SBX_REPO}}/Dockerfile.sandbox" -o "{{.BUILD_DIR}}/Dockerfile.sandbox"
    - cmd: curl -fsSL "{{.SBX_REPO}}/Dockerfile.sandbox-common" -o "{{.BUILD_DIR}}/Dockerfile.sandbox-common"
    - cmd: >-
        docker build -t "{{.SBX_BASE}}"
        -f "{{.BUILD_DIR}}/Dockerfile.sandbox"
        "{{.BUILD_DIR}}/"
    # 2. Upstream common (intermediate image)
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
    # 3. Custom layer (uv, gh CLI, Playwright, git config)
    - cmd: >-
        docker build -t "{{.SBX_COMMON}}"
        --build-arg SBX_COMMON_BASE={{.SBX_COMMON_BASE}}
        -f docker/openclaw/Dockerfile.sandbox-custom
        docker/openclaw/
```

### 新規タスク: sandbox:cache-init

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

## ワークフロー例

### 記事コレクター（lifelog リポジトリ）

```bash
# sandbox 内
cd /workspace
git clone --depth=1 https://github.com/user/dotfiles.git
cd dotfiles

git checkout -b feat/article-collector
# ... ファイル編集 ...
uv sync  # キャッシュヒットで高速

git add -A
git commit -m "feat: add article collector for lifelog"
git push -u origin feat/article-collector
gh pr create --title "Add article collector" --body "Automated by OpenClaw"
```

### ML プロジェクト

```bash
# sandbox 内
cd /workspace
git clone --depth=1 https://github.com/user/ml-project.git
cd ml-project

uv sync  # 初回: PyTorch DL、2回目以降: キャッシュヒット
python train.py

git checkout -b experiment/new-model
git add results/
git commit -m "experiment: new model results"
git push -u origin experiment/new-model
gh pr create --title "New model experiment results"
```

## 不要と判断したもの

| 項目                        | 理由                                                                              |
| --------------------------- | --------------------------------------------------------------------------------- |
| Rust/Cargo                  | リポジトリに Rust プロジェクトなし。Nix でフォーマッター等は代替可能。~300MB 削減 |
| Named volumes               | OpenClaw 2026.3.x 未サポート。binds で代替                                        |
| Project-specific Dockerfile | リポジトリに sandbox 固有ファイルを置きたくない。Fat image + キャッシュで対応     |
| Gateway 仲介型              | OpenClaw に仲介機能なし。実装コスト大。Git-native で十分                          |

## セキュリティ考慮

- `GITHUB_TOKEN` は fine-grained PAT（対象リポジトリ限定）
- `capDrop: ALL` + `readOnlyRoot: true` は維持
- binds のパスは `/app/data/workspace/.cache/` 配下に限定（機密データなし）
- PR レビューが最終的なセーフティゲート
