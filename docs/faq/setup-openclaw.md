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
  ├─ consent.json に openclaw_enabled が未設定
  │   → プロンプト: セットアップする番号を選択
  │   → 結果を ~/.config/dotfiles/consent.json に自動記録
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

`chezmoi apply` 側は `.chezmoidata/personal.yaml` の `openclaw_enabled: true` と `.chezmoiignore.tmpl` で制御されます。consent.json とは独立しており、テンプレート展開用のフラグです。

## 選択の変更

初回の対話確認で選択した結果は `~/.config/dotfiles/consent.json` に永続化されます。
選択を変更したい場合：

```json
// ~/.config/dotfiles/consent.json
{
  "openclaw_enabled": true
}
```

`openclaw_enabled` を `true` / `false` に変更してください。

## 前提条件

OpenClaw をセットアップするには以下が必要です：

| 要件                                      | 用途                           |
| ----------------------------------------- | ------------------------------ |
| Docker Desktop (WSL2 backend)             | コンテナ実行環境               |
| 1Password デスクトップアプリ + CLI (`op`) | シークレット取得               |
| chezmoi                                   | 設定ファイルのテンプレート展開 |

## 関連ドキュメント

- [docker/openclaw/README.md](../../docker/openclaw/README.md) - Docker 構成の詳細・トラブルシューティング
- [docs/architecture.md](../architecture.md) - ハンドラーの実行順序と全体アーキテクチャ
- [docs/scripts/powershell/handler-development.md](../scripts/powershell/handler-development.md) - ハンドラー開発ガイド
