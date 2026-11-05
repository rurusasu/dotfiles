#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  ADAPTER="$REPO_ROOT/scripts/sh/ci-nix.sh"
  export CI_STATE="$BATS_TEST_TMPDIR/state" NIX_CALLS="$BATS_TEST_TMPDIR/nix-calls"
  export TESTED_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  export SOURCE_PATH=/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-source
  export SYSTEM_PATH=/nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-system
  export DRIVER_PATH=/nix/store/cccccccccccccccccccccccccccccccc-driver
  export PYTHON_PATH=/nix/store/dddddddddddddddddddddddddddddddd-python
  export CHECKS_JSON='["/nix/store/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-unit.drv","/nix/store/ffffffffffffffffffffffffffffffff-native-linux-vm-driver.drv"]'
  export CHECKS_EXIT=0 BUILD_EXIT=0 DRIVER_EXIT=0
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$CI_STATE" "$HOME" "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  : >"$NIX_CALLS"
  cat >"$BATS_TEST_TMPDIR/bin/nix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$NIX_CALLS"
case "$1" in
flake) printf '{"path":"%s","inputs":{}}\n' "$SOURCE_PATH" ;;
eval)
  if [[ -n ${CI_SOURCE_ROOT:-} ]]; then
    printf '{"python":{"path":"%s","drv":"%s.drv"},"curl":{"path":"%s-curl","drv":"%s-curl.drv"},"jq":{"path":"%s-jq","drv":"%s-jq.drv"}}\n' \
      "$PYTHON_PATH" "$PYTHON_PATH" "$PYTHON_PATH" "$PYTHON_PATH" "$PYTHON_PATH" "$PYTHON_PATH"
  elif [[ " $* " == *' --expr builtins.currentSystem '* ]]; then
    printf '%s\n' x86_64-linux
  else
    (( CHECKS_EXIT == 0 )) || exit "$CHECKS_EXIT"
    printf '%s\n' "$CHECKS_JSON"
  fi
  ;;
build)
  (( BUILD_EXIT == 0 )) || exit "$BUILD_EXIT"
  case "$*" in
  *native-linux-vm.driver*) printf '%s\n' "$DRIVER_PATH" ;;
  *nixosConfigurations.nixos*) printf '%s\n' "$SYSTEM_PATH" ;;
  *nixpkgs#python3*) printf '%s\n' "$PYTHON_PATH" ;;
  esac
  ;;
*) exit 64 ;;
esac
EOF
  cat >"$BATS_TEST_TMPDIR/bin/install" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'install %s\n' "$*" >>"$NIX_CALLS"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
  printf '{"path":"%s"}\n' "$SOURCE_PATH" >"$CI_STATE/source.json"
}

fixture_repository() {
  local fixture="$BATS_TEST_TMPDIR/repository"
  mkdir -p "$fixture/scripts/sh"
  cp "$ADAPTER" "$fixture/scripts/sh/ci-nix.sh"
  cp "$REPO_ROOT/scripts/sh/retry-ci-dns.sh" "$fixture/scripts/sh/retry-ci-dns.sh"
  printf '{}\n' >"$fixture/flake.lock"
  git -C "$fixture" init -q
  git -C "$fixture" config user.name 'CI Test'
  git -C "$fixture" config user.email ci@example.test
  git -C "$fixture" add .
  git -C "$fixture" commit -qm fixture
  export TESTED_SHA
  TESTED_SHA=$(git -C "$fixture" rev-parse HEAD)
  ADAPTER="$fixture/scripts/sh/ci-nix.sh"
}

@test "CI source rejects stale SHA and staged or unstaged source changes before Nix runs" {
  fixture_repository
  expected=$TESTED_SHA
  TESTED_SHA=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  run bash "$ADAPTER" source linux
  [ "$status" -ne 0 ]
  [ ! -s "$NIX_CALLS" ]
  TESTED_SHA=$expected
  printf 'changed\n' >>"$BATS_TEST_TMPDIR/repository/flake.lock"
  for staged in false true; do
    if [[ $staged == true ]]; then git -C "$BATS_TEST_TMPDIR/repository" add flake.lock; fi
    run bash "$ADAPTER" source linux
    [ "$status" -ne 0 ]
    [ ! -s "$NIX_CALLS" ]
  done
  git -C "$BATS_TEST_TMPDIR/repository" restore --source=HEAD --staged --worktree .
  run bash "$ADAPTER" source linux
  [ "$status" -eq 0 ]
  [ "$(jq -r .path "$CI_STATE/source.json")" = "$SOURCE_PATH" ]
  [ "$(cat "$CI_STATE/python-path")" = "$PYTHON_PATH" ]
}

@test "CI producer builds every discovered check driver and rejects empty or failed discovery" {
  export CI_LINUX_REQUIRED=true
  run bash "$ADAPTER" checks linux
  [ "$status" -eq 0 ]
  grep -Fq '/nix/store/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-unit.drv^*' "$NIX_CALLS"
  grep -Fq '/nix/store/ffffffffffffffffffffffffffffffff-native-linux-vm-driver.drv^*' "$NIX_CALLS"
  [ "$(grep -c '^build ' "$NIX_CALLS")" -eq 1 ]
  for failure in empty discovery build; do
    : >"$NIX_CALLS"
    CHECKS_JSON='[]' CHECKS_EXIT=0 BUILD_EXIT=0
    case $failure in
    discovery) CHECKS_EXIT=43 ;;
    build)
      CHECKS_JSON='["/nix/store/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-unit.drv"]'
      BUILD_EXIT=47
      ;;
    esac
    run bash "$ADAPTER" checks linux
    [ "$status" -ne 0 ]
    if [[ $failure != build ]]; then
      run grep -q '^build ' "$NIX_CALLS"
      [ "$status" -eq 1 ]
    fi
  done
}

@test "Linux producer realizes native and WSL outputs without executing VM runtime" {
  export CI_LINUX_REQUIRED=true CI_WSL_REQUIRED=true
  run bash "$ADAPTER" build linux
  [ "$status" -eq 0 ]
  [ "$(jq -r .driver "$CI_STATE/roots-linux.json")" = "$DRIVER_PATH" ]
  [ "$(jq -r .system "$CI_STATE/roots-wsl.json")" = "$SYSTEM_PATH" ]
  grep -Fq '#nixosConfigurations.linux.config.system.build.toplevel' "$NIX_CALLS"
  grep -Fq '#homeConfigurations.x86_64-linux.activationPackage' "$NIX_CALLS"
  grep -Fq '#checks.x86_64-linux.native-linux-vm.driver' "$NIX_CALLS"
  run grep -Fq nixos-test-driver "$NIX_CALLS"
  [ "$status" -eq 1 ]
  [ ! -e "$CI_STATE/linux-e2e-passed" ]
}

@test "Linux consumer runs the supplied driver and propagates runtime failure without building" {
  driver="$BATS_TEST_TMPDIR/driver"
  mkdir -p "$driver/bin" "$CI_STATE/artifacts/linux"
  cat >"$driver/bin/nixos-test-driver" <<'EOF'
#!/usr/bin/env bash
printf 'runtime invoked\n'
exit "$DRIVER_EXIT"
EOF
  chmod +x "$driver/bin/nixos-test-driver"
  jq -n --arg driver "$driver" '{driver:$driver}' >"$CI_STATE/artifacts/linux/roots.json"
  DRIVER_EXIT=49
  run bash "$ADAPTER" run-vm linux
  [ "$status" -ne 0 ]
  [[ $output == *'runtime invoked'* ]]
  DRIVER_EXIT=0
  run bash "$ADAPTER" run-vm linux
  [ "$status" -eq 0 ]
  [ ! -s "$NIX_CALLS" ]
}

@test "mandatory artifact compression does not depend on optional cache preparation" {
  export CI_WSL_REQUIRED=true CI_LINUX_REQUIRED=false
  python="$BATS_TEST_TMPDIR/python"
  export PREPARED_ZSTD="$BATS_TEST_TMPDIR/zstd"
  mkdir -p "$python/bin" "$PREPARED_ZSTD/bin"
  printf '%s\n' "$python" >"$CI_STATE/python-path"
  jq -n --arg python "$python" --arg zstd "$PREPARED_ZSTD" \
    '{python:{path:$python},zstd:{path:$zstd}}' >"$CI_STATE/tools.json"
  jq -n --arg source "$SOURCE_PATH" '{path:$source,inputs:{}}' >"$CI_STATE/source.json"
  jq -n --arg system "$SYSTEM_PATH" '{system:$system}' >"$CI_STATE/roots-wsl.json"
  cat >"$python/bin/python3" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ $PATH == "$PREPARED_ZSTD/bin:"* ]]
[[ $1 == -B && $3 == export ]]
mkdir -p "$CI_STATE/artifacts/wsl"
EOF
  chmod +x "$python/bin/python3"
  run bash "$ADAPTER" export linux
  [ "$status" -eq 0 ]
  [ "$(cat "$CI_STATE/artifacts/wsl/bootstrap-python-path.txt")" = "$python" ]
}

@test "Darwin consumer invokes the public installer with frozen inputs and source builds disabled" {
  source="$BATS_TEST_TMPDIR/source"
  mkdir -p "$source" "$CI_STATE/artifacts/darwin"
  export INSTALL_CALLS="$BATS_TEST_TMPDIR/install-calls" INSTALL_EXIT=51 GITHUB_ACTIONS=true
  cat >"$source/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ $UPDATE_FLAKE_INPUTS == false && $DOTFILES_ALLOW_BUILDS == false ]]
printf '%s\n' "$DOTFILES_FLAKE_REF" >"$INSTALL_CALLS"
exit "$INSTALL_EXIT"
EOF
  chmod +x "$source/install.sh"
  jq -n --arg source "$source" --arg system "$SYSTEM_PATH" \
    '{source:$source, system:$system, deployment:"/nix/store/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-deployment"}' \
    >"$CI_STATE/artifacts/darwin/roots.json"
  cat >"$BATS_TEST_TMPDIR/bin/launchctl" <<'EOF'
#!/usr/bin/env bash
[[ $1 == print && $2 == gui/* ]]
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/launchctl"
  run bash "$ADAPTER" apply darwin
  [ "$status" -eq 51 ]
  [ "$(cat "$INSTALL_CALLS")" = '/nix/store/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-deployment#macos' ]
  grep -qx preserve-existing-hermes-state "$HOME/.hermes/memories/dotfiles-ci-state-preservation.txt"
  [ ! -s "$NIX_CALLS" ]
}
