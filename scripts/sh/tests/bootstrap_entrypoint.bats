#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  TEST_HOME="$BATS_TEST_TMPDIR/home"
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
  mkdir -p "$TEST_HOME" "$STUB_BIN"
  export COMMAND_LOG

  write_stub curl 'printf "curl %s\n" "$*" >>"$COMMAND_LOG"'
  write_stub git 'exit 0'
  write_stub tar '
printf "tar %s\n" "$*" >>"$COMMAND_LOG"
[[ "$1 $2" == "-xz -C" ]] || exit 64
mkdir -p "$3/nvim-linux-x86_64/bin"
printf "#!/usr/bin/env bash\nexit 0\n" >"$3/nvim-linux-x86_64/bin/nvim"
chmod +x "$3/nvim-linux-x86_64/bin/nvim"
'
  write_stub dpkg 'exit 0'
  write_stub apt-get 'exit 0'
  write_stub sudo 'exec "$@"'
  write_stub chezmoi 'echo "chezmoi stub"; exit 0'
  write_stub nvim '
printf "nvim %s\n" "$*" >>"$COMMAND_LOG"
[[ "$*" == *"--headless --clean -u NONE -i NONE"* ]] || exit 64
[[ "$*" == *"type(vim.pack.add)"* ]] || exit 64
[[ "$NVIM_PACK_ADD_SUPPORTED" == 1 ]]
'
  write_stub uname 'printf "x86_64\n"'
}

write_stub() {
  local name="$1"
  local body="$2"
  cat >"$STUB_BIN/$name" <<EOF
#!/usr/bin/env bash
set -euo pipefail
$body
EOF
  chmod +x "$STUB_BIN/$name"
}

@test "bootstrap.sh keeps capable Neovim and reinstalls when vim.pack.add is unavailable" {
  export HOME="$TEST_HOME"
  export PATH="$STUB_BIN:$PATH"

  for supported in 1 0; do
    export NVIM_PACK_ADD_SUPPORTED="$supported"
    : >"$COMMAND_LOG"
    run timeout 30 bash "$REPO_ROOT/bootstrap.sh" 2>&1
    [ "$status" -eq 0 ]
    [[ $output == *"bootstrap complete"* ]]
    grep -Fq -- 'type(vim.pack.add)' "$COMMAND_LOG"
    if [ "$supported" -eq 1 ]; then
      ! grep -q '^curl ' "$COMMAND_LOG"
      ! grep -q '^tar ' "$COMMAND_LOG"
    else
      [[ $output == *"vim.pack.add is unavailable; will reinstall"* ]]
      grep -Fq -- 'https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz' "$COMMAND_LOG"
      grep -q '^tar ' "$COMMAND_LOG"
      [ -x "$TEST_HOME/.local/nvim/bin/nvim" ]
      [ "$TEST_HOME/.local/bin/nvim" -ef "$TEST_HOME/.local/nvim/bin/nvim" ]
    fi
  done
}
