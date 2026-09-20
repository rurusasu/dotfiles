#!/usr/bin/env bats

setup() {
  REPO_ROOT="${GHOSTTY_TEST_REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}"
  command -v chezmoi >/dev/null || skip "chezmoi required; also exercised by the ghostty-config Nix check"
  mkdir -p "$BATS_TEST_TMPDIR/home"
}

render() {
  chezmoi --config /dev/null --config-format toml --source "$REPO_ROOT/chezmoi" \
    --destination "$BATS_TEST_TMPDIR/home" \
    --cache "$BATS_TEST_TMPDIR/cache" \
    --persistent-state "$BATS_TEST_TMPDIR/state.boltdb" \
    --override-data "{\"chezmoi\":{\"os\":\"$1\"}}" \
    execute-template --file "$REPO_ROOT/chezmoi/.chezmoiscripts/deploy/terminals/run_onchange_deploy.sh.tmpl"
}

@test "terminal deployment installs Ghostty alongside WezTerm on macOS and Linux" {
  for os in darwin linux; do
    test_home="$BATS_TEST_TMPDIR/$os"
    mkdir -p "$test_home"
    rendered="$(render "$os")"
    run env HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" CHEZMOI_SOURCE_DIR="$REPO_ROOT/chezmoi" bash -c "$rendered"
    [ "$status" -eq 0 ]
    [ -f "$test_home/.config/ghostty/config" ]
    cmp "$REPO_ROOT/chezmoi/terminals/ghostty/config" "$test_home/.config/ghostty/config"
    cmp "$REPO_ROOT/chezmoi/terminals/wezterm/wezterm.lua" "$test_home/.config/wezterm/wezterm.lua"
    run env HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" CHEZMOI_SOURCE_DIR="$REPO_ROOT/chezmoi" bash -c "$rendered"
    [ "$status" -eq 0 ]
  done
}

@test "Ghostty deployment does not run on Windows" {
  rendered="$(render windows)"
  [ -z "$rendered" ]
}

@test "Ghostty deployment respects XDG_CONFIG_HOME" {
  rendered="$(render linux)"
  run env HOME="$BATS_TEST_TMPDIR/home" XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/custom config" CHEZMOI_SOURCE_DIR="$REPO_ROOT/chezmoi" bash -c "$rendered"
  [ "$status" -eq 0 ]
  cmp "$REPO_ROOT/chezmoi/terminals/ghostty/config" "$BATS_TEST_TMPDIR/custom config/ghostty/config"
  [ ! -e "$BATS_TEST_TMPDIR/home/.config/ghostty/config" ]
}
