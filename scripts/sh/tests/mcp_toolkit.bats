#!/usr/bin/env bats

setup() {
  export DOCKER_CONFIG="$BATS_TEST_TMPDIR/docker"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  unset DOTFILES_MCP_ONEPASSWORD_CONFIG
  unset MCP_TOOLKIT_OP_ACCOUNT
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export MCP_TOOLKIT_SCRIPT="${MCP_TOOLKIT_SCRIPT:-$BATS_TEST_DIRNAME/../mcp-toolkit.sh}"
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$XDG_CONFIG_HOME/mcp"
  cat >"$XDG_CONFIG_HOME/mcp/onepassword.json" <<'JSON'
{
  "account": "fixture-account",
  "dockerMcp": {
    "exa.api_key": "op://fixture/search/credential",
    "github.personal_access_token": "op://fixture/github/credential"
  }
}
JSON
  cat >"$BATS_TEST_TMPDIR/bin/op" <<'SH'
#!/usr/bin/env bash
[[ $* == *"${MCP_TOOLKIT_OP_ACCOUNT:-fixture-account}"* && $* == *op://fixture/* ]] || exit 2
if [[ ${MCP_TEST_FAIL_READ:-0} == 1 && $* == *op://fixture/github/* ]]; then
  exit 1
fi
if [[ ${MCP_TEST_MULTILINE:-0} == 1 ]]; then
  printf 'fixture-token\n'
  exit 0
fi
printf '%s' 'fixture-token'
SH
  cat >"$BATS_TEST_TMPDIR/bin/docker-mcp" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'fixture-gateway'
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/op" "$BATS_TEST_TMPDIR/bin/docker-mcp"
}

@test "catalog secrets publish privately and preserve the previous file on failed or multiline reads" {
  run bash "$MCP_TOOLKIT_SCRIPT" secrets
  [ "$status" -eq 0 ]
  [ "$(stat -c '%a' "$DOCKER_CONFIG/mcp/secrets.env")" = 600 ]
  grep -q '^github.personal_access_token=fixture-token$' "$DOCKER_CONFIG/mcp/secrets.env"
  cp "$DOCKER_CONFIG/mcp/secrets.env" "$BATS_TEST_TMPDIR/previous.env"

  export DOTFILES_MCP_ONEPASSWORD_CONFIG="$BATS_TEST_TMPDIR/custom-catalog.json"
  mv "$XDG_CONFIG_HOME/mcp/onepassword.json" "$DOTFILES_MCP_ONEPASSWORD_CONFIG"
  export MCP_TOOLKIT_OP_ACCOUNT="override-account"
  run bash "$MCP_TOOLKIT_SCRIPT" secrets
  [ "$status" -eq 0 ]
  export MCP_TEST_FAIL_READ=1
  run bash "$MCP_TOOLKIT_SCRIPT" secrets
  [ "$status" -ne 0 ]
  cmp "$BATS_TEST_TMPDIR/previous.env" "$DOCKER_CONFIG/mcp/secrets.env"

  unset MCP_TEST_FAIL_READ
  export MCP_TEST_MULTILINE=1
  run bash "$MCP_TOOLKIT_SCRIPT" secrets
  [ "$status" -ne 0 ]
  cmp "$BATS_TEST_TMPDIR/previous.env" "$DOCKER_CONFIG/mcp/secrets.env"
}
