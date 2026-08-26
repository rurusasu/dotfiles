# CLI Tools Install Patterns

公式 Docker イメージがないツール群。GitHub Releases から静的バイナリをダウンロード。

## starship (cross-shell prompt)

musl 静的バイナリ。ファイル名にバージョン含まず `/releases/latest/download/` 可。

OK:

```dockerfile
ARG STARSHIP_VERSION=1.24.2
RUN curl -fsSL "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-x86_64-unknown-linux-musl.tar.gz" \
  | tar xz -C /usr/local/bin starship
```

NG:

```dockerfile
RUN curl -fsSL https://starship.rs/install.sh | sh -s -- --yes
```

Why: `curl | sh` より GitHub Releases 直接ダウンロードの方が再現性が高く安全。

Source: <https://github.com/starship/starship/releases>

## zoxide (smarter cd)

musl 静的バイナリ。ファイル名にバージョンを含む。

OK:

```dockerfile
ARG ZOXIDE_VERSION=0.9.9
RUN curl -fsSL "https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/zoxide-${ZOXIDE_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
  | tar xz -C /usr/local/bin zoxide
```

NG:

```dockerfile
RUN curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
```

Why: install script はデフォルトで `~/.local/bin/` にインストールするため、パス設定が必要になる。GitHub Releases なら直接 `/usr/local/bin/` に配置可能。

Source: <https://github.com/ajeetdsouza/zoxide/releases>

## fzf (fuzzy finder)

Go 静的バイナリ。アーカイブルートに `fzf` バイナリのみ。

OK:

```dockerfile
ARG FZF_VERSION=0.67.0
RUN curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_amd64.tar.gz" \
  | tar xz -C /usr/local/bin fzf
```

NG:

```dockerfile
RUN git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && ~/.fzf/install
```

Why: git clone + install script はビルド不要なバイナリに対してオーバーヘッドが大きい。

Source: <https://github.com/junegunn/fzf/releases>

## fd (find alternative)

musl 静的バイナリ。サブディレクトリに格納されるため `--strip-components=1` が必要。

OK:

```dockerfile
ARG FD_VERSION=10.3.0
RUN curl -fsSL "https://github.com/sharkdp/fd/releases/download/v${FD_VERSION}/fd-v${FD_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
  | tar xz --strip-components=1 -C /usr/local/bin "fd-v${FD_VERSION}-x86_64-unknown-linux-musl/fd"
```

NG:

```dockerfile
RUN \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  apt-get update && apt-get install -y fd-find
```

Why: Debian パッケージ名は `fd-find` でバイナリ名は `fdfind`。GitHub Releases なら `fd` のまま使える。

Source: <https://github.com/sharkdp/fd/releases>

## ripgrep (grep alternative)

musl 静的バイナリ（amd64 のみ。arm64 は GNU リンク）。サブディレクトリ格納。

OK:

```dockerfile
ARG RIPGREP_VERSION=15.1.0
RUN curl -fsSL "https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
  | tar xz --strip-components=1 -C /usr/local/bin "ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl/rg"
```

NG:

```dockerfile
RUN \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  apt-get update && apt-get install -y ripgrep
```

Why: Debian パッケージはバージョンが古い場合がある。GitHub Releases なら最新版を確実に取得。

Source: <https://github.com/BurntSushi/ripgrep/releases>

## ghq (Git repository manager)

Go 静的バイナリ。**zip 形式**のため `unzip` が必要。

OK:

```dockerfile
ARG GHQ_VERSION=1.8.1
RUN set -eux; \
  curl -fsSL "https://github.com/x-motemen/ghq/releases/download/v${GHQ_VERSION}/ghq_linux_amd64.zip" \
    -o /tmp/ghq.zip; \
  unzip -o /tmp/ghq.zip -d /tmp/ghq; \
  install -m 755 /tmp/ghq/ghq /usr/local/bin/ghq; \
  rm -rf /tmp/ghq /tmp/ghq.zip
```

NG:

```dockerfile
RUN go install github.com/x-motemen/ghq@latest
```

Why: Go ツールチェーンがイメージに残る。GitHub Releases なら追加依存不要。

Source: <https://github.com/x-motemen/ghq/releases>

## chezmoi (dotfiles manager)

musl 静的バイナリ。tar.gz と単体バイナリの両方が提供される。

OK:

```dockerfile
ARG CHEZMOI_VERSION=2.69.3
RUN curl -fsSL "https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VERSION}/chezmoi_${CHEZMOI_VERSION}_linux-musl_amd64.tar.gz" \
  | tar xz -C /usr/local/bin chezmoi
```

NG:

```dockerfile
RUN sh -c "$(curl -fsLS get.chezmoi.io)"
```

Why: install script はデフォルトで `./bin/` にインストール。GitHub Releases なら直接 `/usr/local/bin/` に配置可能でバージョン固定も容易。

Source: <https://github.com/twpayne/chezmoi/releases>

## task (task runner)

Go 静的バイナリ（`CGO_ENABLED=0`）。Docker Hub イメージは古いため非推奨。

OK:

```dockerfile
ARG TASK_VERSION=3.48.0
RUN curl -fsSL "https://github.com/go-task/task/releases/download/v${TASK_VERSION}/task_${TASK_VERSION}_linux_amd64.tar.gz" \
  | tar xz -C /usr/local/bin task
```

NG:

```dockerfile
COPY --from=taskfile/task:latest /usr/local/bin/task /usr/local/bin/task
```

Why: Docker Hub イメージ（`taskfile/task`）は v3.39.2 で停止しており最新版に追従していない。GitHub Releases が確実。

Source: <https://github.com/go-task/task/releases>

## gh (GitHub CLI)

Go 静的バイナリ（CGO なし）。公式 Docker イメージなし。tarball 内はサブディレクトリ構造。

OK:

```dockerfile
ARG GH_VERSION=2.86.0
RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
  | tar xz --strip-components=2 -C /usr/local/bin "gh_${GH_VERSION}_linux_amd64/bin/gh"
```

NG:

```dockerfile
RUN \
  --mount=type=cache,target=/var/lib/apt,sharing=locked \
  --mount=type=cache,target=/var/cache/apt,sharing=locked \
  set -eux; \
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg; \
  echo "deb [signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list; \
  apt-get update; \
  apt-get install -y --no-install-recommends gh
```

Why: apt リポジトリ追加は GPG キー管理のオーバーヘッドがある。Go 静的バイナリは GitHub Releases から直接取得が最速。

Source: <https://github.com/cli/cli/releases>

## uv (Python package manager)

公式 Docker イメージあり（`ghcr.io/astral-sh/uv`）。`COPY --from` が公式推奨。

OK:

```dockerfile
COPY --from=ghcr.io/astral-sh/uv:0.10.0 /uv /uvx /usr/local/bin/
```

NG:

```dockerfile
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
```

Why: install script はデフォルトで `~/.local/bin/` にインストール。`COPY --from` はネットワーク不要で最速。

Source: <https://docs.astral.sh/uv/guides/integration/docker/>

## git-gtr (git worktree runner)

Bash スクリプト。バイナリなし。`git clone` + symlink が唯一の方法。

OK:

```dockerfile
ARG GIT_GTR_VERSION=v2.1.0
RUN git clone --depth 1 --branch ${GIT_GTR_VERSION} \
  https://github.com/coderabbitai/git-worktree-runner.git /opt/git-worktree-runner \
  && ln -s /opt/git-worktree-runner/bin/git-gtr /usr/local/bin/git-gtr
```

NG:

```dockerfile
RUN sudo git clone https://github.com/coderabbitai/git-worktree-runner.git /opt/git-worktree-runner
```

Why: `sudo` は不要（root で実行）、`--depth 1 --branch` でバージョン固定と最小クローン。

Source: <https://github.com/coderabbitai/git-worktree-runner>

## pre-commit (Git hooks framework)

Python 必要。uv がある環境では `uv tool install` が最適。

OK:

```dockerfile
RUN uv tool install pre-commit --with pre-commit-uv
ENV PATH="/root/.local/bin:$PATH"
```

NG:

```dockerfile
RUN pip install pre-commit
```

Why: `pip install` はシステム Python を汚染する。`uv tool install` は隔離環境にインストール。`pre-commit-uv` プラグインで hook の依存解決も高速化。

Source: <https://docs.astral.sh/uv/guides/integration/pre-commit/>

## 一括インストールパターン

単一 RUN でレイヤーを最小化:

```dockerfile
ARG STARSHIP_VERSION=1.24.2
ARG ZOXIDE_VERSION=0.9.9
ARG FZF_VERSION=0.67.0
ARG FD_VERSION=10.3.0
ARG RIPGREP_VERSION=15.1.0
ARG GHQ_VERSION=1.8.1
ARG CHEZMOI_VERSION=2.69.3
ARG TASK_VERSION=3.48.0
ARG GH_VERSION=2.86.0
ARG GIT_GTR_VERSION=v2.1.0

RUN set -eux; \
  curl -fsSL "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-x86_64-unknown-linux-musl.tar.gz" \
    | tar xz -C /usr/local/bin starship; \
  curl -fsSL "https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/zoxide-${ZOXIDE_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    | tar xz -C /usr/local/bin zoxide; \
  curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_amd64.tar.gz" \
    | tar xz -C /usr/local/bin fzf; \
  curl -fsSL "https://github.com/sharkdp/fd/releases/download/v${FD_VERSION}/fd-v${FD_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    | tar xz --strip-components=1 -C /usr/local/bin "fd-v${FD_VERSION}-x86_64-unknown-linux-musl/fd"; \
  curl -fsSL "https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    | tar xz --strip-components=1 -C /usr/local/bin "ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl/rg"; \
  curl -fsSL "https://github.com/x-motemen/ghq/releases/download/v${GHQ_VERSION}/ghq_linux_amd64.zip" \
    -o /tmp/ghq.zip; \
  unzip -o /tmp/ghq.zip -d /tmp/ghq; \
  install -m 755 /tmp/ghq/ghq /usr/local/bin/ghq; \
  rm -rf /tmp/ghq /tmp/ghq.zip; \
  curl -fsSL "https://github.com/twpayne/chezmoi/releases/download/v${CHEZMOI_VERSION}/chezmoi_${CHEZMOI_VERSION}_linux-musl_amd64.tar.gz" \
    | tar xz -C /usr/local/bin chezmoi; \
  curl -fsSL "https://github.com/go-task/task/releases/download/v${TASK_VERSION}/task_${TASK_VERSION}_linux_amd64.tar.gz" \
    | tar xz -C /usr/local/bin task; \
  curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
    | tar xz --strip-components=2 -C /usr/local/bin "gh_${GH_VERSION}_linux_amd64/bin/gh"; \
  git clone --depth 1 --branch ${GIT_GTR_VERSION} \
    https://github.com/coderabbitai/git-worktree-runner.git /opt/git-worktree-runner; \
  ln -s /opt/git-worktree-runner/bin/git-gtr /usr/local/bin/git-gtr
```
