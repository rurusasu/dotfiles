#!/usr/bin/env bash
# Nix build integration: arguments are the evaluated HM stage runner and files.
set -euo pipefail
activation=$1
home_files=$2
config_directory=${3:-.config}
suite=$(mktemp -d "$TMPDIR/neovim-activation.XXXXXX")
generation="$suite/generation"
mkdir -p "$generation"
ln -s "$home_files" "$generation/home-files"

new_home() {
  export HOME="$suite/$1-home"
  export XDG_CONFIG_HOME="$HOME/$config_directory"
  export XDG_DATA_HOME="$HOME/.local/share"
  export XDG_STATE_HOME="$HOME/.local/state"
  export XDG_CACHE_HOME="$HOME/.cache"
  mkdir -p "$HOME"
}

legacy_config() {
  mkdir -p "$XDG_CONFIG_HOME/nvim/lua/config" \
    "$XDG_CONFIG_HOME/nvim/after/lsp" "$XDG_CONFIG_HOME/nvim/after/ftplugin"
  printf '%s\n' '-- personal init' >"$XDG_CONFIG_HOME/nvim/init.lua"
  chmod 600 "$XDG_CONFIG_HOME/nvim/init.lua"
  printf '%s\n' 'return 42' >"$XDG_CONFIG_HOME/nvim/lua/config/personal.lua"
  printf '%s\n' 'return { custom = true }' >"$XDG_CONFIG_HOME/nvim/after/lsp/nixd.lua"
  printf '%s\n' '-- keep unrelated after content' >"$XDG_CONFIG_HOME/nvim/after/ftplugin/lua.lua"
}

snapshot_home() {
  find "$HOME" -printf '%P %y %m %T@ %l\n' | sort
  find "$HOME" -type f -exec sha256sum '{}' + | sort
}

new_home upgrade
legacy_config
before=$(snapshot_home)
"$activation" "$generation" check
test "$(snapshot_home)" = "$before"
# HM treats a present but empty DRY_RUN as a dry run, too.
DRY_RUN= "$activation" "$generation" apply
test "$(snapshot_home)" = "$before"
# The migration's run guard also respects a nonexported activation variable.
# Run only through the write boundary/migration in this mode: upstream HM's
# external linker itself requires DRY_RUN to be exported.
"$activation" "$generation" dry-run-local
test "$(snapshot_home)" = "$before"
"$activation" "$generation" apply
test -L "$XDG_CONFIG_HOME/nvim/init.lua"
test -L "$XDG_CONFIG_HOME/nvim/lua"
test "$(readlink "$XDG_CONFIG_HOME/nvim/init.lua")" = "$home_files/$config_directory/nvim/init.lua"
test "$(readlink "$XDG_CONFIG_HOME/nvim/lua")" = "$home_files/$config_directory/nvim/lua"
test "$(cat "$XDG_CONFIG_HOME/nvim/init.lua.pre-home-manager")" = '-- personal init'
test "$(stat -c '%a' "$XDG_CONFIG_HOME/nvim/init.lua.pre-home-manager")" = 600
test "$(cat "$XDG_CONFIG_HOME/nvim/lua.pre-home-manager/config/personal.lua")" = 'return 42'
test "$(cat "$XDG_CONFIG_HOME/nvim/after/lsp.pre-home-manager/nixd.lua")" = 'return { custom = true }'
test ! -e "$XDG_CONFIG_HOME/nvim/after/lsp"
test "$(cat "$XDG_CONFIG_HOME/nvim/after/ftplugin/lua.lua")" = '-- keep unrelated after content'
before=$(snapshot_home)
"$activation" "$generation" apply
test "$(snapshot_home)" = "$before"
nvim --headless -i NONE -c 'lua assert(vim.fn.stdpath("config") == os.getenv("XDG_CONFIG_HOME") .. "/nvim")' -c 'qa!'

# A late candidate collision prevents even the earlier init.lua backup and
# prevents HM's forced links. Files and directory metadata remain unchanged.
new_home collision
legacy_config
mkdir "$XDG_CONFIG_HOME/nvim/after/lsp.pre-home-manager"
printf '%s\n' 'older backup' >"$XDG_CONFIG_HOME/nvim/after/lsp.pre-home-manager/keep"
before=$(snapshot_home)
if "$activation" "$generation" apply >"$suite/collision.log" 2>&1; then
  echo 'Expected the evaluated activation to reject the backup collision' >&2
  exit 1
fi
grep -q 'backup already exists' "$suite/collision.log"
test "$(snapshot_home)" = "$before"

for kind in foreign dangling; do
  new_home "$kind"
  mkdir -p "$XDG_CONFIG_HOME/nvim"
  target="$suite/$kind-target"
  if [[ $kind == foreign ]]; then
    mkdir "$target"
  fi
  ln -s "$target" "$XDG_CONFIG_HOME/nvim/lua"
  before=$(snapshot_home)
  if "$activation" "$generation" apply >"$suite/$kind.log" 2>&1; then
    echo "Expected the evaluated activation to reject the $kind symlink" >&2
    exit 1
  fi
  grep -q 'foreign or dangling symlink' "$suite/$kind.log"
  test "$(snapshot_home)" = "$before"
done

new_home fresh
"$activation" "$generation" apply
test -L "$XDG_CONFIG_HOME/nvim/init.lua"
test -L "$XDG_CONFIG_HOME/nvim/lua"
test ! -e "$XDG_CONFIG_HOME/nvim/init.lua.pre-home-manager"
test ! -e "$XDG_CONFIG_HOME/nvim/lua.pre-home-manager"
echo 'Neovim legacy migration passed the evaluated Home Manager file-activation stages'
