#!/usr/bin/env bash

# Install the Codex CLI from npm for Linux, macOS, WSL, and devcontainers.
# Keep the prefix user-local so setup never requires sudo and `codex update`
# can identify the installation as an npm package.

dotfiles_install_codex_npm() {
  local prefix="${CODEX_NPM_PREFIX:-$HOME/.local/npm}"

  command -v npm >/dev/null 2>&1 || {
    printf 'npm is required to install the Codex CLI.\n' >&2
    return 1
  }

  mkdir -p "$prefix"
  NPM_CONFIG_PREFIX="$prefix" npm install --global --no-audit --no-fund @openai/codex@latest
  export PATH="$prefix/bin:$PATH"
  hash -r 2>/dev/null || true

  command -v codex >/dev/null 2>&1 || {
    printf 'Codex CLI was installed but is not available on PATH.\n' >&2
    return 1
  }
  codex --version >/dev/null
}
