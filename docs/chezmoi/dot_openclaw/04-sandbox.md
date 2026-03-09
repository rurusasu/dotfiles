# Sandbox 設定

OpenClaw の `agents.defaults.sandbox` セクションに関する設定ドキュメント。

サンドボックスは各エージェントの実行環境を隔離し、安全にツール実行やコード実行を行うための Docker コンテナ環境を提供する。

## 基本設定

| キー                     | 値          | 説明                                                   |
| ------------------------ | ----------- | ------------------------------------------------------ |
| `sessionToolsVisibility` | `"all"`     | セッション内の全ツールを可視化                         |
| `mode`                   | `"all"`     | 全エージェントをサンドボックス内で実行                 |
| `scope`                  | `"session"` | 同一セッション内のエージェント間でサンドボックスを共有 |
| `workspaceAccess`        | `"rw"`      | ワークスペースへの読み書きアクセスを許可               |

### mode の選択肢

| 値         | 動作                                             |
| ---------- | ------------------------------------------------ |
| `off`      | サンドボックスを使用しない                       |
| `non-main` | メインエージェント以外をサンドボックスで実行     |
| `all`      | 全エージェントをサンドボックスで実行（最大隔離） |

### scope の選択肢

| 値        | 動作                                         |
| --------- | -------------------------------------------- |
| `session` | 同一セッション内でサンドボックスを共有       |
| `agent`   | エージェントごとに個別のサンドボックスを作成 |
| `shared`  | 全セッション間でサンドボックスを共有         |

## Docker 設定

### コンテナ基本設定

| キー             | 値                                      | 説明                              |
| ---------------- | --------------------------------------- | --------------------------------- |
| `docker.image`   | `openclaw-sandbox-common:bookworm-slim` | カスタムビルドイメージ            |
| `docker.network` | `bridge`                                | Docker ブリッジネットワークを使用 |
| `docker.user`    | `0:0`                                   | root ユーザーで実行               |

カスタムサンドボックスイメージには以下のツールがプリインストールされている:

- gh CLI (GitHub CLI)
- Playwright CLI (@playwright/cli)
- Chromium
- その他開発ツール

### セキュリティ設定

| キー                  | 値                             | 説明                                       |
| --------------------- | ------------------------------ | ------------------------------------------ |
| `docker.readOnlyRoot` | `true`                         | ルートファイルシステムを読み取り専用に設定 |
| `docker.tmpfs`        | `["/tmp", "/var/tmp", "/run"]` | 書き込み可能な tmpfs マウント              |
| `docker.capDrop`      | `["ALL"]`                      | 全ケーパビリティを削除                     |

> **注**: `capAdd` と `shmSize` は OpenClaw `2026.3.x` のスキーマで未サポート。設定すると起動時にバリデーションエラーとなる（2026-03-09 に削除済み）。

### リソース制限

| キー                | 値    | 説明                  |
| ------------------- | ----- | --------------------- |
| `docker.pidsLimit`  | `256` | プロセス数上限        |
| `docker.memory`     | `1g`  | メモリ上限            |
| `docker.memorySwap` | `2g`  | メモリ + スワップ上限 |
| `docker.cpus`       | `1`   | CPU コア数上限        |

### 環境変数

| キー                                  | 値                                                         | 説明                                  |
| ------------------------------------- | ---------------------------------------------------------- | ------------------------------------- |
| `docker.env.GITHUB_TOKEN`             | secrets から取得                                           | GitHub API アクセス用                 |
| `docker.env.GH_TOKEN`                 | secrets から取得                                           | gh CLI 用                             |
| `docker.env.PLAYWRIGHT_BROWSERS_PATH` | `/root/.cache/ms-playwright`                               | Playwright ブラウザのインストールパス |
| `docker.env.GIT_CONFIG_COUNT`         | `1`                                                        | git の環境変数ベース設定の数          |
| `docker.env.GIT_CONFIG_KEY_0`         | `url.https://x-access-token:<TOKEN>@github.com/.insteadOf` | GitHub URL の書き換えキー             |
| `docker.env.GIT_CONFIG_VALUE_0`       | `https://github.com/`                                      | 書き換え対象の URL プレフィックス     |

### Git 認証（insteadOf 方式）

Gateway コンテナでは `GIT_ASKPASS` + `git-credential-askpass.sh` で認証しているが、sandbox イメージにはこのスクリプトが存在しない。そのため sandbox では git の `url.<base>.insteadOf` 機能を環境変数経由（`GIT_CONFIG_*`）で設定し、`https://github.com/` を `https://x-access-token:<TOKEN>@github.com/` に自動書き換えすることで認証を実現する。

## パスマッピング

Gateway コンテナの `/app/data/workspace/` が sandbox 内では `/workspace/` にマウントされる。sandbox 内のツール（`shell_exec`, `file_write` 等）では `/workspace/` パスを使用すること。`/app/data/` パスは sandbox 内に存在しない。

| Gateway コンテナ               | sandbox コンテナ      | 用途                 |
| ------------------------------ | --------------------- | -------------------- |
| `/app/data/workspace/`         | `/workspace/`         | ワークスペースルート |
| `/app/data/workspace/lifelog/` | `/workspace/lifelog/` | lifelog データ       |
| `/app/data/workspace/skills/`  | `/workspace/skills/`  | スキル               |

## Prune 設定

サンドボックスコンテナの自動クリーンアップ設定。

| キー               | 値   | 説明                                       |
| ------------------ | ---- | ------------------------------------------ |
| `prune.idleHours`  | `24` | アイドル状態が 24 時間続いたコンテナを削除 |
| `prune.maxAgeDays` | `7`  | 作成から 7 日経過したコンテナを削除        |

## GC 自動化（セーフティネット）

OpenClaw の prune 設定に加え、OpenClaw cron で 1 時間ごとに停止済みコンテナを自動削除する。
OpenClaw プロセスの異常終了や gateway 再起動時に孤立した sandbox コンテナを回収する目的。

| キー | 値          | 説明                                          |
| ---- | ----------- | --------------------------------------------- |
| cron | `0 * * * *` | 毎時 0 分に実行                               |
| 対象 | exited      | 停止済み sandbox コンテナのみ（実行中は除外） |

## 設計判断

### mode="all" の採用理由

全エージェントをサンドボックス内で実行することで、最大限の隔離を実現する。ホスト環境への意図しない変更を防止できる。

### scope="session" の採用理由

同一セッション内のエージェント間でサンドボックスを共有することで、コンテナの起動コストを抑えつつ、セッション間の隔離を維持する。

### readOnlyRoot + tmpfs の組み合わせ

ルートファイルシステムを読み取り専用にすることで、コンテナ内でのファイル改竄を防止する。必要な書き込み領域は tmpfs で提供し、コンテナ停止時に自動消去される。

### root ユーザー (0:0) の使用理由

- サンドボックス内でのツールインストールに root 権限が必要

### capAdd / shmSize の削除理由

OpenClaw `2026.3.x` でスキーマ未サポートのため削除。Playwright CLI は `--no-sandbox` でデフォルト起動するため影響なし。

## セキュリティに関する注意事項

| リスク    | 詳細                                 | 緩和策                                           |
| --------- | ------------------------------------ | ------------------------------------------------ |
| root 実行 | コンテナ内で root 権限を持つ         | readOnlyRoot + capDrop ALL による権限最小化      |
| トークン  | GITHUB_TOKEN が sandbox 内に存在する | Fine-grained PAT（対象リポジトリ限定）で被害限定 |

## 参考リンク

- [OpenClaw Gateway Configuration](https://docs.openclaw.ai/gateway/configuration)
