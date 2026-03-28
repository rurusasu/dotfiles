# OpenClaw メモリシステム移行: SuperLocalMemory + Ollama

**日付:** 2026-03-29
**ステータス:** Approved
**対象リポジトリ:** openclaw-k8s

## 概要

OpenClaw の Kind クラスタにおけるメモリ・ナレッジシステムを再構成する。
cognee-skills + FalkorDB を廃止し、SuperLocalMemory (SLM) + Ollama に統合する。

## 動機

- cognee-skills は FalkorDB + Gemini API + Cognee SDK に依存しており、外部依存が多い
- SLM は 4 チャネルハイブリッド検索 (semantic, BM25, entity graph, temporal) を単一プロセスで提供
- Ollama をクラスタ内に配置することで、埋め込み・LLM 推論を完全ローカル化
- FalkorDB を廃止し、Pod 数とリソース消費を削減

## アーキテクチャ

```
Kind クラスタ (openclaw namespace)
┌──────────────────────────────────────────────────┐
│  openclaw-gateway                                │
│    ├─ openclaw-mcp-bridge                        │
│    │    └─ superlocalmemory:3000/mcp             │
│    ├─ memory.backend: "qmd" (既存維持)           │
│    └─ memorySearch.provider: "ollama" (新規)     │
│                                                  │
│  superlocalmemory (新規 Pod)                     │
│    ├─ Mode B (Ollama 連携)                       │
│    ├─ MCP サーバー (port 3000)                   │
│    ├─ skills_tools ラッパー (改善ループ移植)      │
│    ├─ PVC: slm-data (5Gi)                        │
│    └─ Service: superlocalmemory:3000 (ClusterIP) │
│                                                  │
│  ollama (新規 Pod)                               │
│    ├─ イメージ: ollama/ollama                     │
│    ├─ Service: ollama:11434 (ClusterIP, 全 Pod)  │
│    ├─ PVC: ollama-data (10Gi)                    │
│    └─ 利用者: SLM, gateway (memorySearch), 汎用  │
└──────────────────────────────────────────────────┘
```

## 廃止対象

| リソース                 | 種別            | 理由                     |
| ------------------------ | --------------- | ------------------------ |
| cognee-skills Deployment | Pod             | SLM に機能統合           |
| falkordb Deployment      | Pod             | SLM 内蔵ストレージで代替 |
| cognee-skills Service    | Service         | 不要                     |
| falkordb Service         | Service         | 不要                     |
| cognee-data PVC          | PVC             | 不要                     |
| falkordb-data PVC        | PVC             | 不要                     |
| docker/cognee-skills/    | Docker イメージ | 不要                     |

## 追加リソース

| リソース                    | 種別      | 仕様                                                             |
| --------------------------- | --------- | ---------------------------------------------------------------- |
| superlocalmemory Deployment | Pod       | `npm install -g superlocalmemory`, `slm mcp` で MCP サーバー起動 |
| ollama Deployment           | Pod       | `ollama/ollama` イメージ、CPU のみ                               |
| superlocalmemory Service    | ClusterIP | port 3000                                                        |
| ollama Service              | ClusterIP | port 11434                                                       |
| slm-data PVC                | PVC       | 5Gi — SLM のメモリ DB + learning.db                              |
| ollama-data PVC             | PVC       | 10Gi — モデルファイル永続化                                      |

## SLM 設定

- **Mode:** B (ローカル Ollama 連携)
- **環境変数:**
  - `SLM_MODE=b`
  - `OLLAMA_HOST=http://ollama:11434`
  - `SLM_DATA_DIR=/data` (PVC マウントポイント)
- **MCP サーバー:** `slm mcp` で port 3000 起動
- **プロファイル:** `openclaw` (全エージェント共有)

## Ollama 設定

- **イメージ:** `ollama/ollama:latest`
- **リソース:** 2Gi RAM, 1 CPU (CPU のみ、GPU なし)
- **モデル:** 起動時に自動 pull (init container)
  - 埋め込み: `nomic-embed-text` (~274MB)
  - LLM 推論 (スキル改善提案): `qwen2.5:3b` (~1.9GB) または類似の軽量モデル
- **永続化:** `/root/.ollama` を PVC にマウント

## OpenClaw Gateway 変更

### openclaw-mcp-bridge

cognee-skills エントリを superlocalmemory に置き換え:

```json
"openclaw-mcp-bridge": {
  "servers": {
    "superlocalmemory": {
      "transport": "streamable-http",
      "url": "http://superlocalmemory:3000/mcp",
      "description": "SuperLocalMemory MCP (memory + skill improvement)"
    }
  }
}
```

### memorySearch (オプション)

QMD の埋め込みプロバイダーを Ollama に変更可能:

```json
"memorySearch": {
  "provider": "ollama",
  "model": "nomic-embed-text",
  "ollama": {
    "baseUrl": "http://ollama:11434"
  }
}
```

### cron

`cognee-daily-ingest` ジョブを SLM 対応に書き換え:

- セッショントランスクリプトを `slm remember` で取り込み
- スキルヘルスチェック + 改善提案を Ollama 経由で実行

## スキル改善ループの移植

cognee-skills の skills_tools を SLM API にマッピング:

| cognee 関数                | SLM 代替                              |
| -------------------------- | ------------------------------------- |
| `log_execution()`          | `slm observe` — 実行イベント記録      |
| `calculate_health_score()` | 純 Python ロジック（変更なし）        |
| `get_skill_improvements()` | Ollama LLM で改善提案生成             |
| `amend_skill()`            | ファイル書き込み（変更なし）          |
| `evaluate_amendment()`     | `slm recall` + ヘルススコア比較       |
| `search_knowledge()`       | `slm recall` (4 チャネルハイブリッド) |
| `search_history()`         | `slm recall` (temporal channel)       |
| `ingest_transcript()`      | `slm remember`                        |
| `report_feedback()`        | `slm report_feedback`                 |

## 変更対象ファイル (openclaw-k8s)

### 新規作成

- `docker/superlocalmemory/Dockerfile`
- `docker/superlocalmemory/entrypoint.sh`
- `docker/superlocalmemory/skills_tools/` (cognee-skills から移植・書き換え)
- `base/superlocalmemory/deployment.yaml`
- `base/superlocalmemory/service.yaml`
- `base/superlocalmemory/pvc.yaml`
- `base/ollama/deployment.yaml`
- `base/ollama/service.yaml`
- `base/ollama/pvc.yaml`

### 変更

- `base/kustomization.yaml` — superlocalmemory, ollama 追加。cognee-skills, falkordb 削除
- `base/gateway/configmap.yaml` — MCP bridge, memorySearch, cron 設定更新
- `base/cron/configmap.yaml` — cognee-daily-ingest → slm-daily-ingest
- `docker/gateway/Dockerfile` — QMD ビルド維持、cognee 依存なし
- `Taskfile.yml` — build:cognee-skills → build:superlocalmemory, build:ollama 不要 (公式イメージ)

### 削除

- `base/cognee-skills/` (deployment, service, pvc)
- `base/falkordb/` (deployment, service, pvc)
- `docker/cognee-skills/` (Dockerfile, entrypoint, skills_tools)

## リスクと緩和策

| リスク                                 | 影響                         | 緩和策                                                        |
| -------------------------------------- | ---------------------------- | ------------------------------------------------------------- |
| Ollama CPU 推論が遅い                  | スキル改善提案に時間がかかる | 軽量モデル (3B) を使用。改善提案は cron (日次) なので許容可能 |
| SLM の検索精度が cognee より劣る可能性 | 関連メモリの取りこぼし       | Mode B (Ollama 連携) で 74.8%+ の精度。段階的に評価           |
| Ollama モデル pull が遅い (初回)       | Pod 起動に時間がかかる       | init container で pull、PVC で永続化。2 回目以降はキャッシュ  |
| skills_tools の移植漏れ                | スキル改善が動かない         | テストスクリプトで検証。段階的移植                            |

## 実装フェーズ

### Phase 1: インフラ追加 (Ollama + SLM Pod)

- Ollama Deployment/Service/PVC 作成
- SLM Dockerfile + Deployment/Service/PVC 作成
- Gateway の MCP Bridge に SLM 追加
- smoke test で MCP 接続確認

### Phase 2: skills_tools 移植

- cognee の skills_tools を SLM API + Ollama に書き換え
- ヘルススコア計算ロジックはそのまま移植
- 改善提案生成を Ollama LLM に変更
- cron ジョブの書き換え

### Phase 3: cognee-skills + FalkorDB 廃止

- Gateway ConfigMap から cognee-skills 参照を削除
- base/cognee-skills/, base/falkordb/ マニフェスト削除
- docker/cognee-skills/ 削除
- Taskfile.yml の build:cognee-skills タスク削除
- PVC クリーンアップ
