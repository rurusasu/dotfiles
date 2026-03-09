# モデル設定

OpenClaw のモデル設定に関するドキュメント。
対象フィールド: `agents.defaults.model`, `agents.defaults.models`, `imageModel`, `pdfModel`

設定ファイル: `chezmoi/.chezmoidata/openclaw.yaml` の `openclaw.models` セクション

## 現在の設定値

| キー       | 値                            | エイリアス | 用途                     |
| ---------- | ----------------------------- | ---------- | ------------------------ |
| `primary`  | `openai-codex/gpt-5.4`        | gpt54      | メインのコード生成・推論 |
| `fallback` | `openai-codex/gpt-5.3-codex`  | codex      | プライマリ障害時の代替   |
| `image`    | `openai-codex/gpt-5.4`        | -          | 画像認識・解析           |
| `pdf`      | `anthropic/claude-sonnet-4-6` | sonnet     | PDF 読み取り・解析       |
| `subagent` | `openai-codex/gpt-5.4`        | -          | サブエージェント用       |

エイリアスはコマンドやログに表示される表示名。

## 値の形式

```
provider/model
```

例: `openai-codex/gpt-5.3-codex`, `anthropic/claude-sonnet-4-6`

## 対応プロバイダ (ビルトイン)

| プロバイダ     | 説明                                |
| -------------- | ----------------------------------- |
| `openai`       | OpenAI API (GPT 系)                 |
| `openai-codex` | OpenAI Codex API (コーディング特化) |
| `anthropic`    | Anthropic API (Claude 系)           |
| `google`       | Google AI (Gemini 系)               |
| `mistral`      | Mistral AI                          |
| `groq`         | Groq (高速推論)                     |

## 設定の根拠

- **Primary**: GPT-5.4 は GPT-5.3-Codex のコーディング能力を内包しつつ、汎用知識・エージェント性能が向上（SWE-Bench Pro: 57.7% vs 56.8%）
- **Fallback**: GPT-5.3-Codex はコーディング特化で信頼性が高い。primary がダウンした場合の確実な代替
- **Image**: GPT-5.4 はネイティブ Computer Use 対応で画像解析能力が高い
- **PDF**: Claude Sonnet はネイティブ PDF 解析に対応
- **Subagent**: プライマリと同一モデルを使用し、出力の一貫性を維持

## 変更履歴

### 2026-03-09: GPT-5.4 移行

- OpenClaw を `2026.3.2` → `2026.3.7` にアップデート
- Primary を `openai-codex/gpt-5.3-codex` → `openai-codex/gpt-5.4` に変更
- Fallback を `anthropic/claude-sonnet-4-6` → `openai-codex/gpt-5.3-codex` に変更
- `openclaw agent` コマンドで動作確認済み
- 注: `openai-codex` プロバイダでのコンテキストは 266K（`openai` プロバイダなら 1M だが API Key 必要）

### 既知の問題

- [GitHub issue #37623](https://github.com/openclaw/openclaw/issues/37623): `openai-codex/gpt-5.4` のランタイム 404 は `2026.3.7` で解消済み
- `openai-codex` プロバイダ経由では 266K コンテキスト制限。`openai` プロバイダに切り替えれば 1M 利用可能（要 `OPENAI_API_KEY`）

### 変更時の確認事項

1. OpenClaw のバージョンが対象モデルをサポートしているか確認
2. `openclaw.yaml` の値を変更後、テンプレートをレンダリングして反映
3. `docker compose restart openclaw` でコンテナ再起動
4. `openclaw models list` でエイリアスと認識状態を確認

## リファレンス

- [OpenClaw モデルプロバイダ](https://docs.openclaw.ai/concepts/model-providers)
