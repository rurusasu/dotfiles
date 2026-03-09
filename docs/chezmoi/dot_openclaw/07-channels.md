# チャンネル設定 (channels)

OpenClaw のチャンネル設定セクションに関するドキュメント。
各チャンネルはメッセージングプラットフォームとの接続を定義し、アクセス制御・ストリーミング方式・リトライ戦略を個別に設定できる。

## Telegram (`channels.telegram`)

### 設定値一覧

| キー               | 値                                                 | 説明                                                        |
| ------------------ | -------------------------------------------------- | ----------------------------------------------------------- |
| `enabled`          | `true`                                             | チャンネルの有効/無効                                       |
| `botToken`         | 1Password (`op://Personal/TelegramBot/credential`) | Bot API トークン                                            |
| `dmPolicy`         | `"allowlist"`                                      | DM ポリシー (`pairing` / `allowlist` / `open` / `disabled`) |
| `allowFrom`        | 1Password (`user_id`)                              | 許可するユーザー ID                                         |
| `streaming`        | `"block"`                                          | 応答送信方式 (`block` / `token` / `off`)                    |
| `historyLimit`     | `50`                                               | 保持する会話履歴の上限                                      |
| `replyToMode`      | `"first"`                                          | 返信引用モード                                              |
| `retry.attempts`   | `3`                                                | リトライ回数                                                |
| `retry.minDelayMs` | `400`                                              | 最小リトライ遅延 (ms)                                       |
| `retry.maxDelayMs` | `30000`                                            | 最大リトライ遅延 (ms)                                       |
| `retry.jitter`     | `0.1`                                              | リトライジッター係数                                        |

## Slack (`channels.slack`)

### 設定値一覧

| キー                   | 値                          | 説明                               |
| ---------------------- | --------------------------- | ---------------------------------- |
| `enabled`              | `true`                      | チャンネルの有効/無効              |
| `mode`                 | `"socket"`                  | Socket Mode (公開 URL 不要)        |
| `botToken`             | 1Password                   | Bot トークン                       |
| `appToken`             | 1Password                   | Socket Mode 用アプリレベルトークン |
| `dmPolicy`             | `"allowlist"`               | DM ポリシー                        |
| `allowFrom`            | 1Password (`slack_user_id`) | 許可するユーザー ID                |
| `groupPolicy`          | `"allowlist"`               | グループポリシー                   |
| `streaming`            | `"block"`                   | 応答送信方式                       |
| `historyLimit`         | `100`                       | 保持する会話履歴の上限             |
| `replyToMode`          | `"off"`                     | 返信引用モード                     |
| `thread.historyScope`  | `"thread"`                  | スレッド履歴のスコープ             |
| `thread.inheritParent` | `false`                     | 親メッセージの継承                 |

> **注**: Slack の `retry` セクションは OpenClaw `2026.3.x` のスキーマで未サポート（Telegram では有効）。設定すると起動時にバリデーションエラーとなるため削除済み（2026-03-09）。

### Slack チャンネル設定

4 つのチャンネルが設定済み。すべて `requireMention: true` で動作する。

| チャンネル ID |
| ------------- |
| `C0AK3SQKFV2` |
| `C0AK64UPVNW` |
| `C0AJVDKGN6A` |
| `C0AJZSPV84S` |

## 設計判断

### アクセス制御

- 両チャンネルとも `allowlist` を採用し、指定ユーザーのみがやり取りできるようにしている
- Slack の全チャンネルで `requireMention: true` を設定し、不要な応答ノイズを防止している

### ストリーミング方式

- `streaming="block"` により、トークン単位ではなく完全な応答をまとめて送信する

### 履歴制限

- Telegram は `historyLimit=50`、Slack は `historyLimit=100` に設定
- Slack のスレッドは Telegram より長くなる傾向があるため、より多くの履歴を保持する

### 返信モード

- Telegram では `replyToMode="first"` で最初のメッセージを引用する
- Slack では `replyToMode="off"` に設定。スレッド構造がコンテキストを保持するため引用は不要

### Slack Socket Mode

- Socket Mode を採用し、公開 Webhook URL が不要なシンプルな構成にしている

## セキュリティに関する注意事項

- Bot トークンは 1Password に保管し、設定ファイルに直接記載しない
- `allowlist` で特定のユーザー ID のみにアクセスを制限する
- テンプレートは `lookPath "op"` を使用し、1Password CLI が存在しない環境でもグレースフルにフォールバックする

## 参考リンク

- [OpenClaw Gateway Configuration](https://docs.openclaw.ai/gateway/configuration)
