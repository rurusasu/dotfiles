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
can_install=0
if [ "$(id -u)" -eq 0 ]; then
  can_install=1
elif have sudo; then
  SUDO="sudo"
  can_install=1
else
  log "no sudo and not root — apt install will be skipped"
fi

# ── apt packages (Debian/Ubuntu base only; best effort otherwise) ───────
if [ "$can_install" -eq 1 ] && have apt-get; then
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
elif ! have apt-get; then
  log "apt-get not found — package install skipped (install tmux/curl/git manually)"
fi

# ── modern Neovim (distro nvim is usually too old for lazy.nvim) ────────
# Read --version once with sed `q` so nvim is not killed by SIGPIPE under
# `set -o pipefail` (which would abort the entire script on the
# already-installed path and break idempotency).
need_nvim=1
if have nvim; then
  ver=$(nvim --version 2>/dev/null | sed -n '1{s/^NVIM v\([0-9]*\.[0-9]*\).*/\1/p;q}')
  if [ -z "$ver" ]; then
    log "Neovim present but version string unparseable; will reinstall"
  else
    major=${ver%.*}
    minor=${ver#*.}
    if [ "$major" -gt 0 ] || { [ "$major" -eq 0 ] && [ "$minor" -ge 9 ]; }; then
      need_nvim=0
      log "Neovim $ver already present"
    else
      log "Neovim $ver is too old (need >= 0.9); will reinstall"
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
    # Stage into $tmp, verify, then swap. Never `rm` the existing
    # ~/.local/nvim until the new install is confirmed extracted.
    if ! curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/$asset" |
      tar -xz -C "$tmp"; then
      log "curl/tar failed; aborting (existing nvim untouched)"
      rm -rf "$tmp"
      exit 1
    fi
    new_dir=$(find "$tmp" -maxdepth 1 -type d -name 'nvim-linux-*' | head -1)
    if [ -z "$new_dir" ] || [ ! -d "$new_dir" ]; then
      log "extraction produced no nvim-linux-* dir; aborting (existing nvim untouched)"
      rm -rf "$tmp"
      exit 1
    fi
    old_backup=""
    if [ -e "$HOME/.local/nvim" ]; then
      old_backup="$HOME/.local/nvim.old.$$"
      mv "$HOME/.local/nvim" "$old_backup"
    fi
    mv "$new_dir" "$HOME/.local/nvim"
    ln -sfn "$HOME/.local/nvim/bin/nvim" "$HOME/.local/bin/nvim"
    [ -n "$old_backup" ] && rm -rf "$old_backup"
    rm -rf "$tmp"
  else
    log "skipping Neovim install (arch=$arch, curl/tar missing?)"
  fi
fi

# ── PATH wiring for future shells ───────────────────────────────────────
# `bash -l` (used by `dcnvim`) reads ~/.profile, not ~/.bashrc. Append to
# both so PATH is visible regardless of which init path runs.
for f in "$HOME/.profile" "$HOME/.bashrc"; do
  if ! grep -q '\.local/bin' "$f" 2>/dev/null; then
    printf '\n# Added by dotfiles bootstrap\nexport PATH="$HOME/.local/bin:$PATH"\n' >>"$f"
  fi
done

# ── nvim config symlink ─────────────────────────────────────────────────
# `ln -sfn` does not replace a real directory at the target; check first
# so a stale `~/.config/nvim/` from a previous provisioner is removed.
mkdir -p "$HOME/.config"
target="$HOME/.config/nvim"
if [ -e "$target" ] && [ ! -L "$target" ]; then
  log "removing existing non-symlink $target"
  rm -rf "$target"
fi
ln -sfn "$ROOT/chezmoi/editors/nvim" "$target"
log "linked $target -> $ROOT/chezmoi/editors/nvim"

# ── lazy.nvim plugin pre-warm (best effort) ─────────────────────────────
# stderr goes to a log file so a broken init.lua or plugin compile error
# can be diagnosed rather than blackholed.
NVIM_BIN="$HOME/.local/bin/nvim"
[ -x "$NVIM_BIN" ] || NVIM_BIN="$(command -v nvim 2>/dev/null || true)"
if [ -n "$NVIM_BIN" ] && [ -x "$NVIM_BIN" ]; then
  log "pre-warming lazy.nvim plugins (best effort, 90s cap)"
  lazy_log="$HOME/.local/share/nvim-bootstrap.log"
  mkdir -p "$(dirname "$lazy_log")"
  if ! timeout 90 "$NVIM_BIN" --headless "+Lazy! sync" +qa >"$lazy_log" 2>&1; then
    log "lazy.nvim pre-warm did not complete cleanly; see $lazy_log"
  fi
fi

log "bootstrap complete"
