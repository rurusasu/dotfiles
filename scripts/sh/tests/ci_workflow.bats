#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  WORKFLOW="$REPO_ROOT/.github/workflows/ci-nix.yml"
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN" "$BATS_TEST_TMPDIR/home"
  export HOME="$BATS_TEST_TMPDIR/home"
  export PATH="$STUB_BIN:$PATH" GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output"
  export RUNNER_TEMP="$BATS_TEST_TMPDIR" GITHUB_WORKSPACE="$BATS_TEST_TMPDIR"
  cd "$REPO_ROOT"
}

workflow_step() {
  JOB="$2" STEP="$3" yq -er \
    '(.jobs[strenv(JOB)] // .runs).steps[] | select(.name == strenv(STEP)) | .run' "$1"
}

write_stub() {
  {
    printf '#!/usr/bin/env bash\nset -euo pipefail\n'
    cat
  } >"$STUB_BIN/$1"
  chmod +x "$STUB_BIN/$1"
}

run_script() {
  run bash --noprofile --norc -e -o pipefail -c "$1"
}

@test "native CI authentication bounds cache downloads and keeps tokens private" {
  write_stub nix <<'EOF'
case "$*" in
'config show access-tokens') field=access-tokens ;;
'config show substituters') field=substituters ;;
'config show trusted-public-keys')
  sed -n -E 's/^(extra-)?trusted-public-keys = //p' "$EXPECTED_CONFIG/nix/bootstrap-ci.conf"
  exit 0 ;;
*) exit 64 ;;
esac
grep "^$field = " "$EXPECTED_CONFIG/nix/bootstrap-ci.conf" | cut -d= -f2-
EOF
  for platform in native wsl; do
    fixture="$BATS_TEST_TMPDIR/$platform"
    export HOME="$fixture/home" EXPECTED_CONFIG="$fixture/home/.config"
    export GIT_CONFIG_SYSTEM="$fixture/system-gitconfig" GITHUB_WORKSPACE="$fixture/checkout"
    export GITHUB_TOKEN=fixture-token-not-a-real-secret
    mkdir -p "$HOME"
    unset XDG_CONFIG_HOME NIX_CONFIG NIX_USER_CONF_FILES
    args=()
    if [[ $platform == wsl ]]; then
      args=(--wsl)
      export EXPECTED_CONFIG="$fixture/xdg" XDG_CONFIG_HOME="$fixture/xdg"
      unset GITHUB_WORKSPACE
    fi
    for attempt in 1 2; do
      run bash "$REPO_ROOT/scripts/sh/configure-bootstrap-ci-nix.sh" "${args[@]}"
      [ "$status" -eq 0 ]
      [[ $output != *"$GITHUB_TOKEN"* ]]
    done
    secret_file="$EXPECTED_CONFIG/nix/bootstrap-ci.conf"
    [ "$(stat -c %a "$secret_file" 2>/dev/null || stat -f %Lp "$secret_file")" = 600 ]
    [ "$(grep -Fc "include $secret_file" "$EXPECTED_CONFIG/nix/nix.conf")" -eq 1 ]
    grep -Fxq 'http2 = false' "$secret_file"
    grep -Fxq 'stalled-download-timeout = 60' "$secret_file"
    grep -Fxq 'fallback = true' "$secret_file"
    grep -Fxq 'substituters = https://cache.nixos.org?priority=10 https://cache.numtide.com?priority=50 https://hermes-agent.cachix.org' "$secret_file"
    [ ! -e "$GIT_CONFIG_SYSTEM" ]
    if [[ $platform == wsl ]]; then
      grep -Fxq 'max-jobs = 2' "$secret_file"
    else
      run git config --global --get-all safe.directory
      [ "$status" -eq 0 ]
      [ "$output" = "$GITHUB_WORKSPACE" ]
      ! grep -Fq "$GITHUB_TOKEN" "$HOME/.gitconfig"
    fi
  done
}

@test "bootstrap aggregate fails when a required runtime consumer fails" {
  script=$(workflow_step "$WORKFLOW" complete 'Verify routed job results')
  for variable in $(yq -r '.jobs.complete.env | keys | .[]' "$WORKFLOW"); do
    if [[ $variable == *_RESULT ]]; then export "$variable=success"; else export "$variable=true"; fi
  done
  run_script "$script"
  [ "$status" -eq 0 ]
  export DARWIN_RESULT=failure
  run_script "$script"
  [ "$status" -ne 0 ]
}

git_fixture() {
  mkdir -p "$1"
  cd "$1"
  git init -q
  git config user.email ci@example.test
  git config user.name 'CI Test'
  printf 'fixture\n' >README.md
  git add .
  git commit -qm initial
}

detect_changes() {
  : >"$GITHUB_OUTPUT"
  local script
  script=$(workflow_step "$REPO_ROOT/.github/actions/detect-ci-changes/action.yml" '' 'Classify changed paths')
  run env BASE_SHA="$1" HEAD_SHA="$2" RUN_ALL=false GITHUB_EVENT_NAME=push \
    bash --noprofile --norc -e -o pipefail -c "$script"
}

assert_categories() {
  local name expected
  for name in nix chezmoi other linux darwin wsl windows; do
    expected=false
    if [[ " $* " == *" $name "* ]]; then expected=true; fi
    grep -Fxq "$name=$expected" "$GITHUB_OUTPUT"
  done
  [ "$(wc -l <"$GITHUB_OUTPUT")" -eq 7 ]
}

@test "change detector classifies Git paths and rejects invalid revisions" {
  git_fixture "$BATS_TEST_TMPDIR/revisions"
  base=$(git rev-parse HEAD)
  mkdir -p nix
  printf '#!/bin/sh\n' >nix/example.nix
  git add .
  git commit -qm 'add nix config'
  head=$(git rev-parse HEAD)
  for revision in "$base" 0000000000000000000000000000000000000000; do
    detect_changes "$revision" "$head"
    [ "$status" -eq 0 ]
    assert_categories nix linux darwin wsl
    {
      if [[ $revision == 0000000000000000000000000000000000000000 ]]; then printf 'README.md\0'; fi
      printf 'nix/example.nix\0'
    } >"$BATS_TEST_TMPDIR/expected"
    cmp "$RUNNER_TEMP/ci-changed-paths" "$BATS_TEST_TMPDIR/expected"
  done
  detect_changes missing-base "$head"
  [ "$status" -ne 0 ]
  [ ! -s "$GITHUB_OUTPUT" ]
  detect_changes "$base" missing-head
  [ "$status" -ne 0 ]
  [ ! -s "$GITHUB_OUTPUT" ]
  index=0
  while IFS='|' read -r categories paths; do
    index=$((index + 1))
    git_fixture "$BATS_TEST_TMPDIR/paths-$index"
    base=$(git rev-parse HEAD)
    IFS=';' read -r -a files <<<"$paths"
    for path in "${files[@]}"; do
      path=${path//\\n/$'\n'}
      mkdir -p "$(dirname "$path")"
      printf 'changed\n' >"$path"
    done
    git add .
    git commit -qm 'change classified paths'
    detect_changes "$base" "$(git rev-parse HEAD)"
    [ "$status" -eq 0 ]
    assert_categories $categories
  done <<'EOF'
chezmoi windows|chezmoi/config.tmpl
nix darwin|nix/modules/aerospace/default.nix
nix wsl|nix/modules/1password/op-ssh-sign-wsl
nix wsl|nix/modules/editors/vscode/default.nix
nix linux darwin wsl|nix/modules/1password/default.nix
nix wsl chezmoi windows|nix/modules/fonts/wsl-fontconfig.conf
nix linux darwin wsl chezmoi windows|nix/defaults.nix
nix linux darwin wsl chezmoi windows|nix/home/keybindings/bindings.nix
nix linux darwin wsl chezmoi windows|nix/home/keybindings/generated.json
nix linux darwin wsl chezmoi windows|nix/home/appearance.json
nix linux darwin wsl|nix/modules/terminals/ghostty/default.nix
nix linux darwin wsl chezmoi windows|nix/modules/editors/nvim/neovim.nix
nix linux|nix/modules/hyprland/hyprland-renderer.nix
nix chezmoi windows|windows/winget/packages.json
nix other|scripts/sh/tests/ci_workflow.bats
nix chezmoi other linux darwin wsl windows|scripts/sh/install-macos.sh
nix chezmoi other linux darwin wsl windows|.github/workflows/ci-chezmoi.yml
nix chezmoi other linux darwin wsl windows|taskfiles/hermes/taskfile.yml
|README.md;docs/architecture.md;nix/hosts/AGENTS.md
chezmoi windows|chezmoi/prompt.md
chezmoi windows|chezmoi/dot_codex/AGENTS.md
nix linux darwin wsl|nix/modules/shells/bash/bashrc
other|config/other.json
nix linux darwin wsl chezmoi windows|nix/odd\n name.nix;chezmoi/config.tmpl
EOF
}
