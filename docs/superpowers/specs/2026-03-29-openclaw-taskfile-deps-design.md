# OpenClaw Taskfile 依存ツール自動管理 設計

## 概要

openclaw-k8s の Taskfile タスクが依存するツール (`kind`, `helm`, `kubectl`, `jq`, `docker`) の存在チェックと自動インストールを、OS ごとに適切なパッケージマネージャで行う仕組みを構築する。

## 動機

- `task setup` 実行時に `helm` が未インストールで失敗する問題が発生
- 新環境でのセットアップ時に手動でツールを揃える手間を排除
- Windows / WSL2 / NixOS / macOS の 4 環境をサポート

## 対象ツール

| ツール | 用途 | 必須 |
|--------|------|------|
| `kind` | K8s クラスタ管理 | setup, cluster:* |
| `helm` | ESO/1Password Connect インストール | secrets:* |
| `kubectl` | K8s 操作全般 | ほぼ全タスク |
| `jq` | JSON パース (secrets:status) | secrets:status |
| `docker` | イメージビルド | build:*, sandbox:* |

## ディレクトリ構成

```
tasks/deps/
├── deps.yml            # ツール別インストールタスク定義
├── detect-os.sh        # OS 検出スクリプト
├── install-tool.sh     # 汎用インストーラ
├── test-detect-os.sh   # detect-os.sh のテスト
└── test-install.sh     # install-tool.sh の dry-run テスト
```

## OS 検出 (`detect-os.sh`)

標準出力に OS 識別子を1行出力する。

### 判定ロジック

```
1. uname -s == "Darwin"             → "darwin"
2. /etc/os-release に ID=nixos      → "nixos"
3. /proc/version に microsoft/WSL   → "wsl2"
4. uname -s == "Linux"              → "linux"
5. MSYSTEM が設定 or uname に MINGW → "windows"
6. いずれにも該当しない             → "unknown" (exit 1)
```

### 出力値

`darwin` / `nixos` / `wsl2` / `linux` / `windows`

## インストーラ (`install-tool.sh`)

### インターフェース

```bash
./install-tool.sh <tool-name> [--dry-run]
```

- `<tool-name>`: `kind`, `helm`, `kubectl`, `jq`, `docker` のいずれか
- `--dry-run`: 実行するコマンドを表示するだけで実行しない

### OS 別パッケージマネージャ

| OS | パッケージマネージャ | フォールバック |
|----|----------------------|----------------|
| windows | winget | なし (エラー) |
| wsl2 | apt-get | curl (バイナリ直接) |
| nixos | nix profile install | なし |
| linux | apt-get | curl (バイナリ直接) |
| darwin | brew | curl (バイナリ直接) |

### ツール × OS インストールコマンド

| ツール | windows | wsl2 / linux | nixos | darwin |
|--------|---------|--------------|-------|--------|
| kind | `winget install Kubernetes.kind` | `curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 && install kind /usr/local/bin/` | `nix profile install nixpkgs#kind` | `brew install kind` |
| helm | `winget install Helm.Helm` | `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \| bash` | `nix profile install nixpkgs#kubernetes-helm` | `brew install helm` |
| kubectl | `winget install Kubernetes.kubectl` | `curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && install kubectl /usr/local/bin/` | `nix profile install nixpkgs#kubectl` | `brew install kubectl` |
| jq | `winget install jqlang.jq` | `sudo apt-get install -y jq` | `nix profile install nixpkgs#jq` | `brew install jq` |
| docker | メッセージ表示のみ (*) | メッセージ表示のみ (*) | メッセージ表示のみ (*) | メッセージ表示のみ (*) |

(*) Docker は Docker Desktop / systemd サービスとして管理されるため、自動インストールせずインストール手順を表示して終了する。

### エラーハンドリング

- 未知のツール名 → エラーメッセージ + exit 1
- 未知の OS → エラーメッセージ + exit 1
- インストール失敗 → エラーメッセージ + exit 1
- インストール後に `command -v` で再チェック → 失敗なら PATH 追加を促すメッセージ

## Taskfile 統合 (`deps.yml`)

### タスク定義パターン

```yaml
version: "3"

tasks:
  kind:
    desc: kind をインストール (未検出時のみ)
    status:
      - command -v kind
    cmds:
      - bash tasks/deps/install-tool.sh kind

  helm:
    desc: helm をインストール (未検出時のみ)
    status:
      - command -v helm
    cmds:
      - bash tasks/deps/install-tool.sh helm

  # ... kubectl, jq, docker も同様

  all:
    desc: 全依存ツールをインストール
    deps: [kind, helm, kubectl, jq, docker]

  test:
    desc: deps テストを実行
    cmds:
      - bash tasks/deps/test-detect-os.sh
      - bash tasks/deps/test-install.sh
```

### 各タスクからの参照

```yaml
# tasks/cluster.yml
tasks:
  create:
    deps: [deps:kind, deps:kubectl]
    cmds:
      - kind create cluster ...
```

### Taskfile.yml includes 追加

```yaml
includes:
  deps:
    taskfile: tasks/deps/deps.yml
  # ... 既存の includes
```

## テスト

### test-detect-os.sh

- `detect-os.sh` を実行し出力が許容値リストに含まれるか
- 出力が空でないか
- 終了コードが 0 か
- 出力が1行のみか

### test-install.sh

- `--dry-run` フラグで各ツールを実行
- 出力に期待するコマンド文字列が含まれるか (OS に応じて)
- 未知のツール名でエラーになるか
- 未知の OS でエラーになるか (OS 偽装テスト)

## 既存タスクへの影響

各タスクファイルに `deps:` を追加:

| タスク | 依存 |
|--------|------|
| `cluster:create` | `deps:kind`, `deps:kubectl` |
| `cluster:delete` | `deps:kind` |
| `build:*` | `deps:docker` |
| `deploy:apply` | `deps:kubectl` |
| `secrets:eso`, `secrets:connect` | `deps:helm`, `deps:kubectl` |
| `secrets:connect-creds` | `deps:kubectl` |
| `secrets:status` | `deps:kubectl`, `deps:jq` |
| `ops:*` | `deps:kubectl` |
| `sandbox:*` | `deps:docker` |

## 制約

- `task` (go-task) 自体のインストールはスコープ外 (Taskfile を実行する前提)
- Docker は自動インストールしない (手順表示のみ)
- NixOS では `nix profile install` を使用 (home-manager 管理外)
- Windows の winget は管理者権限が必要な場合がある
