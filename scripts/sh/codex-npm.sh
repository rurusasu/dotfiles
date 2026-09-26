#!/usr/bin/env bash

# Install the Codex CLI from npm for Linux, macOS, WSL, and devcontainers.
# Keep the prefix user-local so setup never requires sudo and `codex update`
# can identify the installation as an npm package.

dotfiles_install_codex_npm() {
  local prefix="${CODEX_NPM_PREFIX:-$HOME/.local/npm}"
  # Acceptance tests may provide an explicit offline npm fixture. Normal
  # installs continue to resolve the npm executable from PATH.
  local npm_command="${DOTFILES_NPM_COMMAND:-npm}"

  if [[ $npm_command == */* ]]; then
    [[ -x $npm_command ]] || {
      printf 'Configured npm executable is not available: %s\n' "$npm_command" >&2
      return 1
    }
  elif ! command -v "$npm_command" >/dev/null 2>&1; then
    printf 'npm is required to install the Codex CLI.\n' >&2
    return 1
  fi

  mkdir -p "$prefix"
  NPM_CONFIG_PREFIX="$prefix" "$npm_command" install --global --no-audit --no-fund @openai/codex@latest
  export PATH="$prefix/bin:$PATH"
  hash -r 2>/dev/null || true

  command -v codex >/dev/null 2>&1 || {
    printf 'Codex CLI was installed but is not available on PATH.\n' >&2
    return 1
  }
  codex --version >/dev/null
}
