# Skills / Plugins 設定

OpenClaw のスキルインストールとプラグイン管理に関する設定セクション。

## Skills 設定

| キー                  | 値      | 説明                                                           |
| --------------------- | ------- | -------------------------------------------------------------- |
| `install.nodeManager` | `"bun"` | スキルパッケージのインストールに使用するパッケージマネージャー |

### 設計判断: bun の採用

npm の代わりに bun を使用することで、スキルパッケージのインストール速度を大幅に向上させている。bun は npm 互換の API を提供しつつ、依存解決とインストールが高速に行われる。

## Plugins 設定

### 許可リスト

| プラグイン名             | 用途                                    |
| ------------------------ | --------------------------------------- |
| `telegram`               | Telegram メッセージング連携             |
| `slack`                  | Slack メッセージング連携                |
| `acpx`                   | Agent Communication Protocol (ACP) 実行 |
| `google-gemini-cli-auth` | Gemini CLI の OAuth トークン管理        |

`allow` リストに明示的に列挙されたプラグインのみがロード可能となる。セキュリティ上、意図しないプラグインの読み込みを防止する仕組み。

### プラグイン個別設定

#### acpx

| キー                          | 値                      | 説明                    |
| ----------------------------- | ----------------------- | ----------------------- |
| `entries.acpx.enabled`        | `true`                  | プラグインの有効化      |
| `entries.acpx.config.command` | `"/usr/local/bin/acpx"` | acpx 実行バイナリのパス |

ACP (Agent Communication Protocol) の実行バックエンドとして機能する。異なる AI システム間でのエージェント間通信を実現する。

#### google-gemini-cli-auth

| キー                                     | 値     | 説明               |
| ---------------------------------------- | ------ | ------------------ |
| `entries.google-gemini-cli-auth.enabled` | `true` | プラグインの有効化 |

Gemini CLI の OAuth トークンを管理し、認証フローを自動化する。

## リファレンス

- [OpenClaw Gateway Configuration](https://docs.openclaw.ai/gateway/configuration)
