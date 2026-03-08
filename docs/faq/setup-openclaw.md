# OpenClaw のセットアップ（オプショナル）

## 概要

OpenClaw は Telegram / Slack 経由で AI エージェントを使うためのゲートウェイです。
Docker コンテナとして動作し、**セットアップは完全にオプショナル**です。

`install.cmd` 実行時に 2 層のゲートで保護されており、明示的に承認しない限りセットアップは行われません。

## セットアップの流れ

### 自動フロー（install.cmd）

`install.cmd` を実行すると、OpenClaw ハンドラー（Order 120）が以下のチェックを行います：

```
Layer 1: 対話確認（永続フラグ）
  ├─ chezmoi.toml に openclaw_enabled が未設定
  │   → プロンプト: "この PC で OpenClaw をセットアップしますか？ [y/N]"
  │   → 結果を ~/.config/chezmoi/chezmoi.toml [data].openclaw_enabled に自動記録
  │   → 承認時: chezmoi apply を自動実行して .openclaw/ 設定を展開
  ├─ openclaw_enabled = true（過去に承認済み）
  │   → プロンプトなしで続行
  └─ openclaw_enabled = false（過去に拒否済み）
      → サイレントスキップ

Layer 2: インフラチェック
  ├─ ~/.openclaw/openclaw.docker.json が存在するか
  ├─ docker コマンドが利用可能か
  └─ docker-compose.yml が存在するか
```

**両方のレイヤーをパスした場合のみ**、Docker コンテナのビルド・起動が実行されます。

### chezmoi apply 単体の場合

`chezmoi apply` 側は `.chezmoidata/personal.yaml` のデフォルト値 `openclaw_enabled: false` と `.chezmoiignore.tmpl` で制御されます。`install.cmd` で承認すると `chezmoi.toml` にフラグが書き込まれるため、以降の `chezmoi apply` でも `.openclaw/` が展開されます。

## 選択の変更

初回の対話確認で選択した結果は `~/.config/chezmoi/chezmoi.toml` に永続化されます。
選択を変更したい場合：

```powershell
# エディタで chezmoi.toml を開く
chezmoi edit-config
```

`[data]` セクションの `openclaw_enabled` を `true` / `false` に変更してください：

```toml
[data]
openclaw_enabled = true   # セットアップを有効化
# openclaw_enabled = false  # セットアップを無効化
```

変更後、`chezmoi apply` を実行すると `.openclaw/` の展開状態が更新されます。

## 前提条件

OpenClaw をセットアップするには以下が必要です：

| 要件 | 用途 |
| --- | --- |
| Docker Desktop (WSL2 backend) | コンテナ実行環境 |
| 1Password デスクトップアプリ + CLI (`op`) | シークレット取得 |
| chezmoi | 設定ファイルのテンプレート展開 |

## 関連ドキュメント

- [docker/openclaw/README.md](../../docker/openclaw/README.md) - Docker 構成の詳細・トラブルシューティング
- [docs/architecture.md](../architecture.md) - ハンドラーの実行順序と全体アーキテクチャ
- [docs/scripts/powershell/handler-development.md](../scripts/powershell/handler-development.md) - ハンドラー開発ガイド
