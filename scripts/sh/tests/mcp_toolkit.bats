#!/usr/bin/env bats

setup() {
  export DOCKER_CONFIG="$BATS_TEST_TMPDIR/docker"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export MCP_TOOLKIT_SCRIPT="${MCP_TOOLKIT_SCRIPT:-$BATS_TEST_DIRNAME/../mcp-toolkit.sh}"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/op" <<'SH'
#!/usr/bin/env bash
if [[ ${MCP_TEST_FAIL_READ:-0} == 1 && $* == *GitHubUsedOpenClawPAT* ]]; then
  exit 1
fi
printf '%s' 'fixture-token'
SH
  cat >"$BATS_TEST_TMPDIR/bin/docker-mcp" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'fixture-gateway'
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/op" "$BATS_TEST_TMPDIR/bin/docker-mcp"
}

@test "secret synchronization publishes privately and preserves the previous file when a read fails" {
  run bash "$MCP_TOOLKIT_SCRIPT" secrets
  [ "$status" -eq 0 ]
  [ "$(stat -c '%a' "$DOCKER_CONFIG/mcp/secrets.env")" = 600 ]
  grep -q '^github.personal_access_token=fixture-token$' "$DOCKER_CONFIG/mcp/secrets.env"
  cp "$DOCKER_CONFIG/mcp/secrets.env" "$BATS_TEST_TMPDIR/previous.env"

  export MCP_TEST_FAIL_READ=1
  run bash "$MCP_TOOLKIT_SCRIPT" secrets
  [ "$status" -ne 0 ]
  cmp "$BATS_TEST_TMPDIR/previous.env" "$DOCKER_CONFIG/mcp/secrets.env"
}
