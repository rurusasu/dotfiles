# ACP (Agent Communication Protocol) 設定

OpenClaw のエージェント間通信プロトコルに関する設定セクション。

## 設定値一覧

| キー | 値 | 説明 |
| --- | --- | --- |
| `enabled` | `true` | ACP 機能の有効化 |
| `backend` | `"acpx"` | ACP 実行バックエンド |
| `dispatch.enabled` | `true` | ACP メッセージのディスパッチ(ルーティング)の有効化 |

## 設計判断

### ACP の有効化

ACP は異なる AI システム間でのエージェント間通信を実現するプロトコル。`enabled: true` にすることで、OpenClaw がマルチエージェント環境のハブとして機能する。

### acpx バックエンド

`backend: "acpx"` は ACP メッセージの実行ランタイムとして acpx を使用する設定。acpx は ACP プロトコルの実行環境を提供し、エージェント間のメッセージ送受信を処理する。実行バイナリのパスは plugins セクションの `entries.acpx.config.command` で指定される。

### ディスパッチの有効化

`dispatch.enabled: true` により、受信した ACP メッセージを適切なエージェントへルーティングする機能が有効になる。これにより、複数エージェントが協調して動作するワークフローが実現できる。

## アーキテクチャ概要

```
外部エージェント  <-->  OpenClaw (ACP dispatch)  <-->  acpx backend  <-->  対象エージェント
```

1. 外部エージェントが ACP メッセージを送信
2. OpenClaw の dispatch がメッセージをルーティング
3. acpx バックエンドがメッセージを実行・転送
4. 対象エージェントが応答を返却

## リファレンス

- [OpenClaw Gateway Configuration](https://docs.openclaw.ai/gateway/configuration)
