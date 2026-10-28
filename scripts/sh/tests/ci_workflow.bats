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

@test "WSL transport remains available when only the consumer is rerun" {
  upload=$(yq -er '.jobs["wsl-prebuild"].steps[] | select(.name == "Upload WSL Nix store cache") | .with.name' "$WORKFLOW")
  download=$(yq -er '.jobs.wsl.steps[] | select(.name == "Download prebuilt WSL Nix store cache") | .with.name' "$WORKFLOW")
  previous=''
  for run_id in 123456 234567; do
    uploaded=${upload//'${{ github.run_id }}'/$run_id}
    uploaded=${uploaded//'${{ github.run_attempt }}'/1}
    [ "$uploaded" != "$previous" ]
    for attempt in 1 2 3; do
      requested=${download//'${{ github.run_id }}'/$run_id}
      requested=${requested//'${{ github.run_attempt }}'/$attempt}
      [ "$requested" = "$uploaded" ]
    done
    previous=$uploaded
  done
  # Rerunning the producer must replace its artifact within the same run.
  [ "$(yq -er '.jobs["wsl-prebuild"].steps[] | select(.name == "Upload WSL Nix store cache") | .with.overwrite' "$WORKFLOW")" = true ]
}

@test "WSL prebuild exports zstd transport and fails closed" {
  script=$(workflow_step "$WORKFLOW" wsl-prebuild 'Build the WSL system closure and export a local cache')
  export STORE_PATH=/nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-hermes
  write_stub nix <<'EOF'
case "$1" in
--version) echo 'nix boundary double' ;;
build)
	[[ " $* " == *' .#nixosConfigurations.nixos.config.system.build.toplevel '* ]]
	printf '%s\n' "$STORE_PATH" ;;
copy)
	[[ $# == 4 && $2 == --to && $4 == "$STORE_PATH" && $3 == file:///*'?compression=zstd' ]]
	((COPY_EXIT == 0)) || exit "$COPY_EXIT"
	cache=${3#file://}
	[[ ${cache#*\?} == compression=zstd ]]
	cache=${cache%\?compression=zstd}
	mkdir -p "$cache/nar"
	printf cache >"$cache/nar/private.nar.zst"
	printf 'StorePath: %s\nURL: %s\nReferences: %s\n' "$STORE_PATH" "$NAR_URL" "$NAR_REFS" \
		>"$cache/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.narinfo" ;;
path-info) [[ $2 == --recursive ]]; printf '%s\n' "$STORE_PATH" ;;
*) exit 64 ;;
esac
EOF
  write_stub nix-store <<'EOF'
[[ "$1 $2 $3 $4" == '--store https://cache.nixos.org --check-validity --print-invalid' ]]
shift 4
printf '%s\n' "$@"
EOF
  for case in success native traversal missing closure; do
    export RUNNER_TEMP="$BATS_TEST_TMPDIR/$case/container runner temp"
    export DOTFILES_CI_BINARY_CACHE="$RUNNER_TEMP/persistent-cache"
    export COPY_EXIT=0 NAR_URL=nar/private.nar.zst NAR_REFS=''
    expected=1 diagnostic=''
    case "$case" in
    success) expected=0 ;;
    native)
      COPY_EXIT=47
      expected=47
      ;;
    traversal)
      NAR_URL=../outside.nar
      diagnostic='Invalid NAR location'
      ;;
    missing)
      NAR_URL=nar/missing.nar
      diagnostic='Missing NAR payload'
      ;;
    closure)
      NAR_REFS=outside-closure
      diagnostic='Incomplete reference closure'
      ;;
    esac
    mkdir -p "$DOTFILES_CI_BINARY_CACHE"
    : >"$GITHUB_OUTPUT"
    run_script "$script"
    [ "$status" -eq "$expected" ]
    if ((expected)); then
      [[ $output == *"$diagnostic"* ]]
      [ ! -s "$GITHUB_OUTPUT" ]
      [ ! -e "$RUNNER_TEMP/wsl-nix-cache-artifact/wsl-nix-cache.tar" ]
    else
      artifact=$(sed -n 's/^artifact-dir=//p' "$GITHUB_OUTPUT")
      [[ $artifact == "$RUNNER_TEMP/"* ]]
      [ "$(ls -1 "$artifact")" = $'wsl-nix-cache.tar\nwsl-system-paths.txt' ]
      [ "$(cat "$artifact/wsl-system-paths.txt")" = "$STORE_PATH" ]
      tar -tf "$artifact/wsl-nix-cache.tar" >"$BATS_TEST_TMPDIR/archive-list"
      grep -Fxq './nar/private.nar.zst' "$BATS_TEST_TMPDIR/archive-list"
      grep -Fxq './public-paths.txt' "$BATS_TEST_TMPDIR/archive-list"
    fi
    if ((COPY_EXIT == 0)); then
      [ -f "$DOTFILES_CI_BINARY_CACHE/nar/private.nar.zst" ]
    fi
  done
}

@test "CI authentication follows Nix home and keeps tokens private" {
  write_stub getent <<'EOF'
printf 'fixture:x:0:0:Fixture:%s:/bin/bash\n' "$FALLBACK_HOME"
EOF
  write_stub nix <<'EOF'
case "$*" in
'config show access-tokens') field=access-tokens ;;
'config show substituters') field=extra-substituters ;;
'config show trusted-public-keys') field=extra-trusted-public-keys ;;
*) exit 64 ;;
esac
grep "^$field = " "$EXPECTED_CONFIG/nix/bootstrap-ci.conf" | cut -d= -f2-
EOF
  for use_xdg in true false; do
    for wsl in true false; do
      for owned_home in true false; do
        fixture="$BATS_TEST_TMPDIR/$use_xdg-$wsl-$owned_home"
        export FALLBACK_HOME="$fixture/passwd-home" HOME="$fixture/missing-home"
        export EXPECTED_CONFIG="$FALLBACK_HOME/.config" GITHUB_ENV="$fixture/github-env"
        export GIT_CONFIG_SYSTEM="$fixture/gitconfig" GITHUB_WORKSPACE="$fixture/checkout"
        export GITHUB_TOKEN=fixture-token-not-a-real-secret
        mkdir -p "$FALLBACK_HOME"
        unset XDG_CONFIG_HOME NIX_CONFIG NIX_USER_CONF_FILES
        if [[ $owned_home == true ]]; then
          HOME=$FALLBACK_HOME
          if [[ $use_xdg == true ]]; then EXPECTED_CONFIG="$fixture/xdg"; fi
        fi
        if [[ $use_xdg == true ]]; then export XDG_CONFIG_HOME="$EXPECTED_CONFIG"; fi
        args=()
        if [[ $wsl == true ]]; then
          args=(--wsl)
          unset GITHUB_WORKSPACE
        fi
        for attempt in 1 2; do
          run bash "$REPO_ROOT/scripts/sh/configure-bootstrap-ci-nix.sh" "${args[@]}"
          [ "$status" -eq 0 ]
          [[ $output != *"$GITHUB_TOKEN"* ]]
        done
        if [[ $owned_home == true ]]; then
          [ ! -e "$GITHUB_ENV" ]
        else
          printf 'HOME=%s\nXDG_CONFIG_HOME=\nHOME=%s\nXDG_CONFIG_HOME=\n' \
            "$FALLBACK_HOME" "$FALLBACK_HOME" >"$fixture/expected-env"
          cmp "$GITHUB_ENV" "$fixture/expected-env"
        fi
        secret_file="$EXPECTED_CONFIG/nix/bootstrap-ci.conf"
        [ "$(stat -c %a "$secret_file" 2>/dev/null || stat -f %Lp "$secret_file")" = 600 ]
        [ "$(grep -Fc "include $secret_file" "$EXPECTED_CONFIG/nix/nix.conf")" -eq 1 ]
        if [[ $wsl == true ]]; then
          [ ! -e "$GIT_CONFIG_SYSTEM" ]
          grep -Fxq 'max-jobs = 2' "$secret_file"
        else
          run git config --system --get-all safe.directory
          [ "$status" -eq 0 ]
          [ "$output" = "$GITHUB_WORKSPACE" ]
          ! grep -Fq "$GITHUB_TOKEN" "$GIT_CONFIG_SYSTEM"
        fi
      done
    done
  done
}

@test "bootstrap aggregate accepts no work and rejects missing required jobs" {
  script=$(workflow_step "$WORKFLOW" complete 'Verify routed job results')
  for changes in '' CHANGES_RESULT=failure LINUX_BUILD_REQUIRED=true NIX_REQUIRED=true \
    BASH_REQUIRED=true 'BASH_REQUIRED=true BASH_RESULT=failure' 'BASH_REQUIRED=true BASH_RESULT=success' \
    BASH_RESULT=success \
    'TOOLS_REQUIRED=true TOOLS_RESULT=success NIX_REQUIRED=true NIX_RESULT=success LINUX_BUILD_REQUIRED=true LINUX_BUILD_RESULT=success' \
    WINDOWS_REQUIRED=true 'WINDOWS_REQUIRED=true WINDOWS_INSTALLER_RESULT=success' WINDOWS_INSTALLER_RESULT=success DARWIN_RESULT=success; do
    while read -r variable; do
      if [[ $variable == *_RESULT ]]; then export "$variable=skipped"; else export "$variable=false"; fi
    done < <(grep -oE '\$\{[A-Z_]+\}' <<<"$script" | tr -d '${}' | sort -u)
    export CHANGES_RESULT=success
    for assignment in $changes; do export "$assignment"; done
    run_script "$script"
    case "$changes" in
    '' | 'BASH_REQUIRED=true BASH_RESULT=success' | 'TOOLS_REQUIRED=true '* | 'WINDOWS_REQUIRED=true WINDOWS_INSTALLER_RESULT=success') [ "$status" -eq 0 ] ;;
    *) [ "$status" -eq 1 ] ;;
    esac
  done
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
nix linux darwin wsl chezmoi windows|nix/modules/terminals/ghostty/ghostty.nix
nix linux darwin wsl chezmoi windows|nix/modules/terminals/ghostty/ghostty-renderer.nix
nix linux darwin wsl chezmoi windows|nix/modules/terminals/ghostty/ghostty-wsl.nix
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
