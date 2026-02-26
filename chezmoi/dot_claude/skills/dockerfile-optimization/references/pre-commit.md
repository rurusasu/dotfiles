# pre-commit Docker Install Patterns

Python ベースの Git hooks フレームワーク。Docker コンテナ内でのインストールには複数の考慮事項がある。

## インストール方法

### uv tool install（推奨）

`uv` がある環境では最速。`pre-commit-uv` プラグインで hook の依存解決も高速化。

OK:

```dockerfile
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/
USER ${USER_NAME}
RUN uv tool install pre-commit --with pre-commit-uv
```

NG:

```dockerfile
RUN pip install pre-commit
```

Why: `pip install` はシステム Python を汚染し、依存関係の競合リスクがある。`uv tool install` は隔離環境にインストール。

### pip（uv が使えない場合）

OK:

```dockerfile
USER ${USER_NAME}
RUN pip install --user --no-cache-dir pre-commit==4.2.0
```

NG:

```dockerfile
RUN pip install pre-commit
```

Why: `--no-cache-dir` なしは pip キャッシュでイメージ肥大化。`--user` なしはシステム Python を汚染。バージョン未指定はビルド再現性がない。

Source: <https://docs.astral.sh/uv/guides/integration/pre-commit/>

## root vs non-root

pre-commit は root 権限不要。セキュリティのため non-root ユーザーでインストール。

OK:

```dockerfile
# System packages は root で
RUN apt-get install -y --no-install-recommends git

# pre-commit は non-root で
USER ${USER_NAME}
RUN uv tool install pre-commit --with pre-commit-uv
```

NG:

```dockerfile
# root のままインストール → セキュリティリスク
RUN pip install --no-cache-dir pre-commit
```

Why: pre-commit 公式が「root access を要求しない」設計を明言。Docker のセキュリティベストプラクティス（CIS Docker Benchmark）でも non-root 推奨。

## PRE_COMMIT_HOME 環境変数

pre-commit は hook 環境を `$PRE_COMMIT_HOME`（デフォルト: `~/.cache/pre-commit`）に保存。Docker コンテナでは明示的に設定すべき。

OK:

```dockerfile
ENV PRE_COMMIT_HOME="/home/${USER_NAME}/.cache/pre-commit"
USER ${USER_NAME}
```

NG:

```dockerfile
# PRE_COMMIT_HOME 未設定 + USER 切り替えで不整合
USER root
RUN pre-commit install-hooks
# キャッシュが /root/.cache/pre-commit に作成される
USER devuser
# devuser から /root/.cache にアクセスできない
```

Why: ユーザー切り替え時にキャッシュの所有権不整合が発生する。明示的な設定で回避。

Source: <https://github.com/pre-commit/pre-commit/issues/1731>

## install vs install-hooks

3つのコマンドの違い:

| コマンド                             | `.git/hooks` スクリプト | hook 仮想環境 |
| ------------------------------------ | ----------------------- | ------------- |
| `pre-commit install`                 | インストール            | しない        |
| `pre-commit install-hooks`           | しない                  | インストール  |
| `pre-commit install --install-hooks` | インストール            | インストール  |

### DevContainer の場合

Dockerfile 内では `pre-commit install` は実行しない。`.git` がないため失敗する。

OK:

```dockerfile
# Dockerfile: ツールのインストールのみ
USER ${USER_NAME}
RUN uv tool install pre-commit --with pre-commit-uv
```

```jsonc
// devcontainer.json: リポジトリマウント後に hook を設定
{
  "postCreateCommand": "pre-commit install",
}
```

NG:

```dockerfile
# Dockerfile 内で pre-commit install（.git が存在しない）
RUN pre-commit install
```

```dockerfile
# 不要な .git がイメージに残る
RUN git init && pre-commit install
```

### CI 専用イメージの場合

hook 環境をプリインストールしてランタイムの初回実行を高速化。

OK:

```dockerfile
COPY .pre-commit-config.yaml /tmp/build/
RUN cd /tmp/build && git init && pre-commit install-hooks && rm -rf /tmp/build
```

NG:

```dockerfile
# ソースコード全体を COPY → コード変更のたびにキャッシュ無効化
COPY . /app
RUN cd /app && pre-commit install-hooks
```

Why: `.pre-commit-config.yaml` だけ先に COPY してレイヤーキャッシュを活用。

## BuildKit cache mount の注意

`--mount=type=cache` と `pre-commit install-hooks` の組み合わせには既知の問題あり。

NG:

```dockerfile
# hook 環境が正しく作成されない（既知の問題）
RUN --mount=type=cache,target=/home/${USER_NAME}/.cache/pre-commit \
  pre-commit install-hooks
```

OK:

```dockerfile
# cache mount なしで確実にインストール
RUN pre-commit install-hooks
```

Why: BuildKit の cache mount はビルド間で共有されるが、pre-commit の hook 環境はシンボリックリンクや特殊なディレクトリ構造を使用するため不整合が発生する。

Source: <https://github.com/pre-commit/pre-commit/issues/2680>

## hook が依存するランタイム

pre-commit の hook は多言語対応（Python, Node, Go, Rust 等）。各言語のランタイムが必要。

OK:

```dockerfile
# ランタイムを事前にインストール（root で）
COPY --from=oven/bun:latest /usr/local/bin/bun /usr/local/bin/bun
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# pre-commit（non-root で）
USER ${USER_NAME}
RUN uv tool install pre-commit --with pre-commit-uv
```

NG:

```dockerfile
# pre-commit だけインストールして依存ランタイムが欠如
USER ${USER_NAME}
RUN uv tool install pre-commit --with pre-commit-uv
# → Node ベースの hook (prettier, eslint) が失敗する
```

Why: `additional_dependencies` を使う hook は対応するパッケージマネージャ（npm, pip 等）がコンテナ内で利用可能である必要がある。

## セキュリティ: hook リポジトリの固定

pre-commit hook は git URL + rev で参照。tag は force-push で改変可能。

OK (`.pre-commit-config.yaml`):

```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: cef0300fd0fc4d2a87a85fa2093c6b283ea36f4b # frozen: v5.0.0
    hooks:
      - id: trailing-whitespace
```

NG:

```yaml
repos:
  - repo: https://github.com/some-user/some-hooks
    rev: v1.0.0
    hooks:
      - id: some-hook
```

Why: tag のみ指定はリポジトリオーナーの force-push で改変可能。commit SHA で固定すれば改変不可能。Renovate / Dependabot で自動更新管理を推奨。

Source: <https://github.com/pre-commit/pre-commit/issues/942>
