#!/usr/bin/env bats

@test "mandatory artifact compression does not depend on optional cache preparation" {
  repository=$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)
  export CI_STATE="$BATS_TEST_TMPDIR/state" PREPARED_ZSTD="$BATS_TEST_TMPDIR/zstd"
  export TESTED_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  python="$BATS_TEST_TMPDIR/python"
  source=/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-source
  system=/nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-system
  mkdir -p "$CI_STATE" "$python/bin" "$PREPARED_ZSTD/bin"
  printf '%s\n' "$python" >"$CI_STATE/python-path"
  jq -n --arg python "$python" --arg zstd "$PREPARED_ZSTD" \
    '{python:{path:$python},zstd:{path:$zstd}}' >"$CI_STATE/tools.json"
  jq -n --arg source "$source" '{path:$source,inputs:{}}' >"$CI_STATE/source.json"
  jq -n --arg system "$system" '{system:$system}' >"$CI_STATE/roots-wsl.json"
  cat >"$python/bin/python3" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ $PATH == "$PREPARED_ZSTD/bin:"* ]]
mkdir -p "$CI_STATE/artifacts/wsl"
EOF
  chmod +x "$python/bin/python3"
  run bash "$repository/scripts/sh/ci-nix.sh" export wsl
  [ "$status" -eq 0 ]
  [ "$(cat "$CI_STATE/artifacts/wsl/bootstrap-python-path.txt")" = "$python" ]
}
