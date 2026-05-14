#!/usr/bin/env bash
# Devcontainer dotfiles bootstrap.
#
# Auto-detected and executed by devcontainer-cli when this repository
# is supplied as `--dotfiles-repository`. Sets up the minimum needed
# for the "host terminal → container tmux+nvim" workflow:
#
#   1. tmux + git + curl + tar via apt (Debian/Ubuntu base only).
#   2. Modern Neovim release into ~/.local/nvim with bin symlink.
#   3. Symlink chezmoi/editors/nvim → ~/.config/nvim.
#   4. Headless lazy.nvim plugin pre-warm (best effort, 90s cap).
#
# Idempotent — safe to re-run on every DevcontainerUp.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

log() { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# ── sudo wrapper ────────────────────────────────────────────────────────
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if have sudo; then
    SUDO="sudo"
  else
    log "no sudo available — apt install will be skipped"
  fi
fi

# ── apt packages (Debian/Ubuntu base only; best effort otherwise) ───────
if have apt-get; then
  need=()
  have tmux || need+=("tmux")
  have curl || need+=("curl")
  have git || need+=("git")
  have tar || need+=("tar")
  if [ "${#need[@]}" -gt 0 ]; then
    log "apt install: ${need[*]}"
    $SUDO apt-get update -qq
    $SUDO env DEBIAN_FRONTEND=noninteractive \
      apt-get install -y -qq --no-install-recommends "${need[@]}"
  fi
else
  log "apt-get not found — package install skipped (install tmux/curl/git manually)"
fi

# ── modern Neovim (distro nvim is usually too old for lazy.nvim) ────────
need_nvim=1
if have nvim; then
  ver=$(nvim --version | head -1 | sed -n 's/^NVIM v\([0-9]*\.[0-9]*\).*/\1/p')
  if [ -n "$ver" ]; then
    major=${ver%.*}
    minor=${ver#*.}
    if [ "$major" -gt 0 ] || { [ "$major" -eq 0 ] && [ "$minor" -ge 9 ]; }; then
      need_nvim=0
      log "Neovim $ver already present"
    fi
  fi
fi

if [ "$need_nvim" -eq 1 ]; then
  arch=$(uname -m)
  case "$arch" in
  x86_64) asset="nvim-linux-x86_64.tar.gz" ;;
  aarch64) asset="nvim-linux-arm64.tar.gz" ;;
  *) asset="" ;;
  esac
  if [ -n "$asset" ] && have curl && have tar; then
    log "installing Neovim release ($asset) to ~/.local/nvim"
    mkdir -p "$HOME/.local/bin"
    tmp=$(mktemp -d)
    curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/$asset" |
      tar -xz -C "$tmp"
    rm -rf "$HOME/.local/nvim"
    mv "$tmp"/nvim-linux-* "$HOME/.local/nvim"
    ln -sfn "$HOME/.local/nvim/bin/nvim" "$HOME/.local/bin/nvim"
    rmdir "$tmp" 2>/dev/null || true
  else
    log "skipping Neovim install (arch=$arch, curl/tar missing?)"
  fi
fi

# ── PATH wiring for future interactive shells ───────────────────────────
if ! grep -q '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
  printf '\n# Added by dotfiles bootstrap\nexport PATH="$HOME/.local/bin:$PATH"\n' \
    >>"$HOME/.bashrc"
fi

# ── nvim config symlink ─────────────────────────────────────────────────
mkdir -p "$HOME/.config"
ln -sfn "$ROOT/chezmoi/editors/nvim" "$HOME/.config/nvim"
log "linked $HOME/.config/nvim -> $ROOT/chezmoi/editors/nvim"

# ── lazy.nvim plugin pre-warm (best effort) ─────────────────────────────
NVIM_BIN="$HOME/.local/bin/nvim"
[ -x "$NVIM_BIN" ] || NVIM_BIN="$(command -v nvim 2>/dev/null || true)"
if [ -n "$NVIM_BIN" ] && [ -x "$NVIM_BIN" ]; then
  log "pre-warming lazy.nvim plugins (best effort, 90s cap)"
  timeout 90 "$NVIM_BIN" --headless "+Lazy! sync" +qa 2>/dev/null ||
    log "lazy.nvim pre-warm timed out or failed — run :Lazy sync inside nvim"
fi

log "bootstrap complete"
