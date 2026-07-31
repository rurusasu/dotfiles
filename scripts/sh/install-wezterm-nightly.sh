#!/usr/bin/env bash
set -euo pipefail

WEZTERM_NIGHTLY_URL="${WEZTERM_NIGHTLY_URL:-https://github.com/wezterm/wezterm/releases/download/nightly/WezTerm-macos-nightly.zip}"
WEZTERM_APP_PATH="${WEZTERM_APP_PATH:-/Applications/WezTerm.app}"
WEZTERM_BIN_DIR="${WEZTERM_BIN_DIR:-/opt/homebrew/bin}"
WEZTERM_BASH_COMPLETION_PATH="${WEZTERM_BASH_COMPLETION_PATH:-/opt/homebrew/etc/bash_completion.d/wezterm}"
WEZTERM_FISH_COMPLETION_PATH="${WEZTERM_FISH_COMPLETION_PATH:-/opt/homebrew/share/fish/vendor_completions.d/wezterm.fish}"
WEZTERM_ZSH_COMPLETION_PATH="${WEZTERM_ZSH_COMPLETION_PATH:-/opt/homebrew/share/zsh/site-functions/_wezterm}"
WEZTERM_CURL_COMMAND="${WEZTERM_CURL_COMMAND:-curl}"

if [[ -d $WEZTERM_APP_PATH ]]; then
  exit 0
fi

for command_name in "$WEZTERM_CURL_COMMAND" unzip find mkdir dirname cp ln rm mktemp; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'required command is missing: %s\n' "$command_name" >&2
    exit 1
  }
done

temporary_directory="$(mktemp -d)"
cleanup() {
  rm -rf "$temporary_directory"
}
trap cleanup EXIT

archive="$temporary_directory/WezTerm-macos-nightly.zip"
extract_directory="$temporary_directory/extracted"
mkdir -p "$extract_directory"
"$WEZTERM_CURL_COMMAND" -fsSL "$WEZTERM_NIGHTLY_URL" -o "$archive"
unzip -q "$archive" -d "$extract_directory"

source_app="$(find "$extract_directory" -type d -name WezTerm.app -print -quit)"
if [[ -z $source_app ]]; then
  printf 'WezTerm.app was not found in the downloaded nightly archive\n' >&2
  exit 1
fi

mkdir -p "$(dirname "$WEZTERM_APP_PATH")"
cp -R "$source_app" "$WEZTERM_APP_PATH"

link_if_present() {
  local source_path="$1"
  local target_path="$2"

  [[ -e $source_path ]] || return 0
  mkdir -p "$(dirname "$target_path")"
  if [[ -e $target_path || -L $target_path ]]; then
    rm -f "$target_path"
  fi
  ln -s "$source_path" "$target_path"
}

link_if_present "$WEZTERM_APP_PATH/Contents/MacOS/wezterm" "$WEZTERM_BIN_DIR/wezterm"
link_if_present "$WEZTERM_APP_PATH/Contents/MacOS/wezterm-gui" "$WEZTERM_BIN_DIR/wezterm-gui"
link_if_present "$WEZTERM_APP_PATH/Contents/MacOS/wezterm-mux-server" "$WEZTERM_BIN_DIR/wezterm-mux-server"
link_if_present "$WEZTERM_APP_PATH/Contents/MacOS/strip-ansi-escapes" "$WEZTERM_BIN_DIR/strip-ansi-escapes"
link_if_present \
  "$WEZTERM_APP_PATH/Contents/Resources/shell-completion/bash" \
  "$WEZTERM_BASH_COMPLETION_PATH"
link_if_present \
  "$WEZTERM_APP_PATH/Contents/Resources/shell-completion/fish" \
  "$WEZTERM_FISH_COMPLETION_PATH"
link_if_present \
  "$WEZTERM_APP_PATH/Contents/Resources/shell-completion/zsh" \
  "$WEZTERM_ZSH_COMPLETION_PATH"
