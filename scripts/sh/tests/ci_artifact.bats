#!/usr/bin/env bats

@test "Nix artifacts preserve provenance and reject corrupt or mismatched payloads" {
  repository=$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)
  run python3 "$repository/scripts/python/tests/test_ci_nix_artifact.py"
  [ "$status" -eq 0 ]
  [[ $output =~ Ran[[:space:]][1-9][0-9]*[[:space:]]tests ]]
}
