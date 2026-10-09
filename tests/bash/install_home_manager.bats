#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  INSTALLER="$REPO_ROOT/scripts/sh/install-home-manager.sh"
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
  ACTIVATION="$BATS_TEST_TMPDIR/home-manager-generation"
  mkdir -p "$STUB_BIN" "$ACTIVATION" "$BATS_TEST_TMPDIR/home"
  export HOME="$BATS_TEST_TMPDIR/home" USER=test-user
  # Keep Nix-provided tools while giving external-command stubs precedence.
  export PATH="$STUB_BIN:$PATH"
  export COMMAND_LOG ACTIVATION
  export DOTFILES_NIX_PROFILE_SCRIPT="$BATS_TEST_TMPDIR/nix-profile.sh"
  unset SUDO_USER
  : >"$COMMAND_LOG"
  : >"$DOTFILES_NIX_PROFILE_SCRIPT"

  write_stub uname 'printf "Linux\n"'
  write_stub nix '
printf "nix %s\n" "$*" >>"$COMMAND_LOG"
if [[ $* == flake\ update\ --flake\ * ]]; then
  exit "${FLAKE_UPDATE_STATUS:-0}"
elif [[ $* == "eval --impure --raw --expr builtins.currentSystem" ]]; then
  printf x86_64-linux
elif [[ $* == *homeConfigurations*activationPackage* ]]; then
  if [[ ${ACTIVATION_BUILD_STATUS:-0} != 0 ]]; then
    exit "$ACTIVATION_BUILD_STATUS"
  fi
  printf "%s\n" "$ACTIVATION"
fi
'
  write_stub chezmoi 'printf "chezmoi %s\n" "$*" >>"$COMMAND_LOG"'
  write_stub npm '
prefix="${NPM_CONFIG_PREFIX:-$HOME/.local/npm}"
mkdir -p "$prefix/bin"
printf "npm %s\n" "$*" >>"$COMMAND_LOG"
printf "#!/usr/bin/env bash\nexit 0\n" >"$prefix/bin/codex"
chmod +x "$prefix/bin/codex"
'
  cat >"$ACTIVATION/activate" <<'EOF'
#!/usr/bin/env bash
printf 'home-manager-activate\n' >>"$COMMAND_LOG"
EOF
  chmod +x "$ACTIVATION/activate"
}

write_stub() {
  local name="$1" body="$2"
  cat >"$STUB_BIN/$name" <<EOF
#!/usr/bin/env bash
set -euo pipefail
$body
EOF
  chmod +x "$STUB_BIN/$name"
}

assert_log_order() {
  local previous=0 pattern line
  for pattern in "$@"; do
    line="$(grep -nF "$pattern" "$COMMAND_LOG" | head -1 | cut -d: -f1)"
    [ -n "$line" ]
    [ "$line" -gt "$previous" ]
    previous="$line"
  done
}

@test "Home Manager activates the Linux user environment before Codex and chezmoi" {
  run "$INSTALLER"

  [ "$status" -eq 0 ]
  grep -q 'build --impure --no-link --print-out-paths .*homeConfigurations.*x86_64-linux.*activationPackage' "$COMMAND_LOG"
  assert_log_order \
    "nix flake update --flake $REPO_ROOT" \
    "homeConfigurations" \
    "home-manager-activate" \
    "npm install --global --no-audit --no-fund @openai/codex@latest" \
    "chezmoi init --source $REPO_ROOT/chezmoi" \
    "chezmoi apply --force"
  [[ "$output" == *"User-only setup complete; Docker/systemd were not configured."* ]]
}

@test "flake update failure stops Home Manager activation" {
  export FLAKE_UPDATE_STATUS=42

  run "$INSTALLER"

  [ "$status" -eq 42 ]
  ! grep -q 'home-manager-activate\|^chezmoi ' "$COMMAND_LOG"
}

@test "Home Manager build failure stops before user configuration" {
  export ACTIVATION_BUILD_STATUS=42

  run "$INSTALLER"

  [ "$status" -eq 42 ]
  ! grep -q 'home-manager-activate\|^chezmoi ' "$COMMAND_LOG"
}
