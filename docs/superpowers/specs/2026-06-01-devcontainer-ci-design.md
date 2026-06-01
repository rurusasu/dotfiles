---
title: devcontainer CLI クロスプラットフォーム CI 設計
date: 2026-06-01
status: implemented
---

# devcontainer CLI クロスプラットフォーム CI 設計

## 目的

`bootstrap.sh` と `.devcontainer/ci/devcontainer.json` が Windows・Linux(Nix)・macOS の 3 プラットフォームで実際に動くことを CI で自動検証する。検証レベルは「`devcontainer up` → `bootstrap.sh` 完走 → tmux + nvim headless 起動」まで。

## アーキテクチャ

```
.devcontainer/ci/
  devcontainer.json   ← CI 専用設定 (image: ubuntu:24.04)
  smoke.sh            ← nvim / tmux / chezmoi バージョン確認
  bats.sh             ← tests/bash/ が存在すれば bats 実行
  e2e.sh              ← tmux new-session + nvim --headless E2E

.github/workflows/ci-devcontainer.yml
  ├── job: linux-nix  (ubuntu-24.04 + Nix + devcontainer CLI via Nix)
  ├── job: macos      (macos-15 + Colima + npm)
  └── job: windows    (windows-2025 + Docker Linux mode + npm)
```

## devcontainer.json 設計

| 項目              | 値                                              | 理由                                                                                          |
| ----------------- | ----------------------------------------------- | --------------------------------------------------------------------------------------------- |
| image             | `ubuntu:24.04`                                  | 最小構成で bootstrap.sh のフルセットアップをテスト                                            |
| postCreateCommand | `bash ${containerWorkspaceFolder}/bootstrap.sh` | CI では `~/.config/devcontainer/devcontainer.json` の dotfiles 機能が使えないため直接呼び出し |
| remoteUser        | `root`                                          | ubuntu:24.04 最小イメージのデフォルトユーザー。sudo なしで apt-get が通る                     |

## E2E 検証フロー

各 job 共通:

1. `devcontainer up` → `postCreateCommand` 経由で `bootstrap.sh` 実行
   - apt: tmux / git / curl / tar
   - chezmoi install + apply (best effort; 1Password template 失敗は継続)
   - nvim install (`~/.local/bin/nvim`)
   - claude code install (best effort)
   - lazy.nvim pre-warm (90s cap)
2. `devcontainer exec -- bash smoke.sh` → nvim / tmux / chezmoi バージョン確認
3. `devcontainer exec -- bash bats.sh` → `tests/bash/` が存在すれば bats 実行
4. `devcontainer exec -- bash e2e.sh` → `tmux new-session -d -s ci "nvim --headless +qa"`

## プラットフォーム固有対応

| Platform  | Docker 準備                                           | CLI インストール                           |
| --------- | ----------------------------------------------------- | ------------------------------------------ |
| linux-nix | ネイティブ                                            | `nix profile install nixpkgs#devcontainer` |
| macos     | `brew install colima docker && colima start`          | `npm install -g @devcontainers/cli`        |
| windows   | `DockerCli.exe -SwitchLinuxEngine` + `Start-Sleep 15` | `npm install -g @devcontainers/cli`        |

## タイムアウト

| job       | timeout | 理由                                  |
| --------- | ------- | ------------------------------------- |
| linux-nix | 30 分   | Docker ネイティブ、Nix キャッシュあり |
| macos     | 45 分   | Colima 起動 + Docker pull             |
| windows   | 45 分   | Linux コンテナ切り替え + Docker pull  |

## エラーハンドリング

| ステップ                        | 失敗時                                         |
| ------------------------------- | ---------------------------------------------- |
| `devcontainer up`               | ジョブ失敗（必須）                             |
| `bootstrap.sh` 内 chezmoi apply | best-effort（継続）                            |
| `bootstrap.sh` 内 claude code   | best-effort（継続）                            |
| smoke test (nvim/tmux/chezmoi)  | ジョブ失敗                                     |
| bats                            | `tests/bash/` 不在はスキップ、失敗はジョブ失敗 |
| tmux+nvim E2E                   | ジョブ失敗                                     |

## トリガー

`bootstrap.sh`, `.devcontainer/**`, `.github/workflows/ci-devcontainer.yml` への push/PR。

## スコープ外

- 実際の dotfiles dotfiles 機能 (`~/.config/devcontainer/devcontainer.json`) のテスト
- claude code の認証・実際の動作確認
- Windows ネイティブ (WSL 外) での devcontainer 起動
