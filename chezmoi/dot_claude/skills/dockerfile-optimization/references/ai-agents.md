# AI Agent CLI Install Patterns

## Claude Code

npm は deprecated。ネイティブインストールを使用する。Node.js 不要。

OK:

```dockerfile
RUN curl -fsSL https://claude.ai/install.sh | bash
```

NG:

```dockerfile
RUN npm install -g @anthropic-ai/claude-code
```

Why: npm インストールは deprecated。ネイティブバイナリは自動更新対応。

Source: <https://code.claude.com/docs/en/setup>

## OpenAI Codex CLI

Node.js 22+ が必要。npm でインストール。

OK:

```dockerfile
RUN npm install -g @openai/codex
```

bun の場合:

```dockerfile
COPY --from=oven/bun:latest /usr/local/bin/bun /usr/local/bin/bun
RUN bun install -g @openai/codex
```

Source: <https://developers.openai.com/codex/quickstart>

## Google Gemini CLI

Node.js 20+ が必要。npm でインストール。公式 Docker イメージあり。

OK (COPY --from):

```dockerfile
COPY --from=google/gemini-cli:latest /usr/local/lib/node_modules/@google/gemini-cli /usr/local/lib/node_modules/@google/gemini-cli
RUN ln -s /usr/local/lib/node_modules/@google/gemini-cli/bin/gemini.js /usr/local/bin/gemini
```

OK (npm):

```dockerfile
RUN npm install -g @google/gemini-cli
```

OK (bun):

```dockerfile
COPY --from=oven/bun:latest /usr/local/bin/bun /usr/local/bin/bun
RUN bun install -g @google/gemini-cli
```

Source: <https://github.com/google-gemini/gemini-cli>

## GitHub Copilot CLI

Node.js 22+ が必要。複数のインストール方法あり。

OK (npm):

```dockerfile
RUN npm install -g @github/copilot
```

OK (bun):

```dockerfile
COPY --from=oven/bun:latest /usr/local/bin/bun /usr/local/bin/bun
RUN bun install -g @github/copilot
```

OK (install script):

```dockerfile
RUN curl -fsSL https://gh.io/copilot-install | bash
```

NG:

```dockerfile
RUN gh extension install github/gh-copilot
```

Why: gh-copilot extension は 2025/10 に deprecated。GitHub Copilot CLI に移行済み。

Source: <https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli>

## Cursor CLI

Claude Code と同様のネイティブインストール方式。npm パッケージ `cursor-cli` は非公式。

OK:

```dockerfile
RUN curl -fsSL https://cursor.com/install | bash
```

NG:

```dockerfile
RUN npm install -g cursor-cli
```

Why: `cursor-cli` npm パッケージは公式ではない。公式はネイティブインストーラー。

Source: <https://cursor.com/docs/cli/installation>

## CodeRabbit CLI

クローズドソース。公式 Docker イメージ・npm パッケージなし。`curl | sh` が唯一の方法。
`unzip` が依存として必要。`~/.local/bin/` にインストールされる。

OK:

```dockerfile
RUN curl -fsSL https://cli.coderabbit.ai/install.sh | sh
```

バージョン固定:

```dockerfile
ARG CODERABBIT_VERSION=v0.3.5
RUN CODERABBIT_VERSION=${CODERABBIT_VERSION} curl -fsSL https://cli.coderabbit.ai/install.sh | sh
```

NG:

```dockerfile
RUN if [ "${INSTALL_DEV_GO_TOOLS}" = "true" ]; then \
  curl -fsSL https://cli.coderabbit.ai/install.sh | sh; \
  fi
```

Why: 条件分岐による optional install は `docker compose` の `target` でステージを切り替えるべき。

Source: <https://docs.coderabbit.ai/cli/overview>
