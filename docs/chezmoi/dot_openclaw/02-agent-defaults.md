# Agent Defaults（agents.defaults）

## 概要

OpenClaw のエージェント実行時に適用されるデフォルトパラメータ。
`openclaw.yaml` の `openclaw.agent` セクションで管理し、chezmoi テンプレート経由で `openclaw.docker.json` に展開される。

## 現在の設定値

| パラメータ        | 値                    | ドキュメントデフォルト  | 説明                                            |
| ----------------- | --------------------- | ----------------------- | ----------------------------------------------- |
| `workspace`       | `/app/data/workspace` | `~/.openclaw/workspace` | エージェントの作業ディレクトリ                  |
| `maxConcurrent`   | `4`                   | -                       | 同時実行可能なエージェント数の上限              |
| `timeoutSeconds`  | `600`                 | -                       | エージェント 1 ターンあたりのタイムアウト（秒） |
| `contextTokens`   | `200000`              | -                       | コンテキストウィンドウのトークン数              |
| `thinkingDefault` | `"low"`               | -                       | 思考レベル（off / low / medium / high / xhigh） |

### 未設定パラメータ（ドキュメントデフォルトを使用）

| パラメータ            | デフォルト値 | 説明                       |
| --------------------- | ------------ | -------------------------- |
| `imageMaxDimensionPx` | `1200`       | 画像の最大寸法（ピクセル） |

## 設定の根拠

### workspace: `/app/data/workspace`

Docker コンテナ内で動作するため、ホストの `~/.openclaw/workspace` ではなくコンテナ内パスを指定。
`openclaw-data` という Docker named volume にマウントされており、コンテナ再起動後もデータが永続化される。

### maxConcurrent: 4

リソース消費と並列性のバランスを取った値。ホストマシンの CPU・メモリに余裕がある場合は増やせるが、
サンドボックスのリソース制限（`sandbox.cpus: 1`, `sandbox.memory: 1g`）を考慮すると 4 が妥当。

### timeoutSeconds: 600

1 ターン 10 分。複雑なタスク（大規模リファクタリング、複数ファイルの解析など）に十分な時間を確保。
サブエージェントは別途 `subagent.runTimeoutSeconds: 300`（5 分）で制限されている。

### contextTokens: 200000

200K トークンのコンテキストウィンドウ。現在のプライマリモデル（gpt-5.3-codex）に対応。
GPT-5.4 は 1M コンテキストをサポートしているため、モデル切り替え時に増加を検討できる。

### thinkingDefault: "low"

ルーティンタスクでのトークン消費を抑えるために `low` に設定。
リクエスト単位でオーバーライド可能なため、複雑な推論が必要な場合は `medium` 以上を指定できる。

| レベル   | 用途                             |
| -------- | -------------------------------- |
| `off`    | 単純な質問応答、フォーマット変換 |
| `low`    | 日常的なコーディングタスク       |
| `medium` | 設計判断を含むタスク             |
| `high`   | 複雑なアーキテクチャ検討         |
| `xhigh`  | 最大限の推論が必要なケース       |

## 注意事項

- **workspace のデータ永続化**: `openclaw-data` named volume で管理されるため、`docker compose down` でもデータは保持される。`docker volume rm` を実行した場合はデータが消失する。
- **GitHub 同期未対応**: workspace データの GitHub 同期はまだ実装されていない。Kubernetes 移行時に検討予定。
- **コンテキストトークンの拡張**: GPT-5.4（1M コンテキスト）への切り替え時に `contextTokens` を増やす場合、`compaction` セクションの `reserveTokensFloor` と `memoryFlushSoftThreshold` も合わせて調整が必要。

## 関連ドキュメント

- [OpenClaw セットアップ](../../faq/setup-openclaw.md) - 初期セットアップの流れ
- [OpenClaw Gateway Configuration](https://docs.openclaw.ai/gateway/configuration) - 公式設定リファレンス
