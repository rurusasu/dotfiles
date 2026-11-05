#!/usr/bin/env bats

@test "Nix artifact transfer and optional cache protect their essential runtime boundaries" {
  repository=$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)
  run python3 -B -W error::ResourceWarning -m unittest discover \
    -s "$repository/scripts/python/tests" -p 'test_*.py' -v
  [ "$status" -eq 0 ]
  [[ $output =~ Ran[[:space:]]+[1-9][0-9]*[[:space:]]+tests? ]]
}
