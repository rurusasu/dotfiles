# Compaction & Context Pruning 設定

OpenClaw の compaction（コンパクション）と context pruning（コンテキスト刈り込み）の設定を記述する。

## Compaction (`agents.defaults.compaction`)

### 現在の設定値

| キー                              | 値            |
| --------------------------------- | ------------- |
| `mode`                            | `"safeguard"` |
| `reserveTokensFloor`              | `24000`       |
| `identifierPolicy`                | `"strict"`    |
| `memoryFlush.enabled`             | `true`        |
| `memoryFlush.softThresholdTokens` | `150000`      |

### 設計根拠

- **`mode="safeguard"`** -- コンテキスト上限に近づいたときのみ compaction を実行する。積極的（aggressive）には行わない。
- **`reserveTokensFloor=24000`** -- 次のレスポンス生成に十分な空きトークンを確保する。
- **`identifierPolicy="strict"`** -- compaction 時に識別子（変数名・関数名等）を正確に保持する。要約による識別子の欠落を防ぐ。
- **`memoryFlush`** -- 150K トークンに達した時点で重要な情報を永続化してから compaction に移行する。

## Context Pruning (`agents.defaults.contextPruning`)

### 現在の設定値

| キー                    | 値                                    |
| ----------------------- | ------------------------------------- |
| `mode`                  | `"cache-ttl"`                         |
| `ttl`                   | `"1h"`                                |
| `keepLastAssistants`    | `3`                                   |
| `softTrimRatio`         | `0.3`                                 |
| `hardClearRatio`        | `0.5`                                 |
| `softTrim.maxChars`     | `4000`                                |
| `softTrim.headChars`    | `1500`                                |
| `softTrim.tailChars`    | `1500`                                |
| `hardClear.enabled`     | `true`                                |
| `hardClear.placeholder` | `"[Old tool result content cleared]"` |

### 設計根拠

- **`mode="cache-ttl"`** -- ツール結果を経過時間に基づいて削除する。古くなった情報を自動的に除去する。
- **`ttl="1h"`** -- ツール結果は 1 時間で期限切れとなる。一般的なコーディング作業には十分な保持期間。
- **`keepLastAssistants=3`** -- 直近 3 件のアシスタントメッセージを常に保持し、会話の流れを維持する。
- **softTrim** -- 大きなツール出力の先頭 1500 文字 + 末尾 1500 文字を残し、中間部分をトリムする。
- **hardClear** -- 非常に古いコンテンツをプレースホルダーに置換し、コンテキストを解放する。

### トークン閾値の目安（contextTokens = 200K の場合）

| 閾値      | 比率  | 発動トークン数 | 動作                     |
| --------- | ----- | -------------- | ------------------------ |
| softTrim  | `0.3` | 60,000         | head+tail を残してトリム |
| hardClear | `0.5` | 100,000        | プレースホルダーに置換   |

## 注意事項

- `contextTokens` が増加した場合（例: GPT-5.4 の 1M コンテキスト）、`softTrimRatio` と `hardClearRatio` の再調整が必要になる可能性がある。
- `softTrimRatio=0.3` は 200K コンテキストで 60K トークン、`hardClearRatio=0.5` は 100K トークンで発動する。
- compaction の `memoryFlush.softThresholdTokens=150000` と pruning の閾値が整合的に動作するよう設計されている。

## 参考

- [OpenClaw Gateway Configuration](https://docs.openclaw.ai/gateway/configuration)
