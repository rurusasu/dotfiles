#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export TEST_LOG="$BATS_TEST_TMPDIR/commands"
  export TEST_CONFIG_LOG="$BATS_TEST_TMPDIR/nix-config"
  unset UPDATE_FLAKE_INPUTS DOTFILES_ALLOW_BUILDS DOTFILES_FLAKE_REF NIX_CONFIG
  export TEST_KERNEL=Microsoft TEST_CURRENT_USER=nixos TEST_CONFIGURED_USER=nixos
  cat >"$BATS_TEST_TMPDIR/bin/uname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$TEST_KERNEL"
EOF
  cat >"$BATS_TEST_TMPDIR/bin/nix" <<'EOF'
#!/usr/bin/env bash
printf 'nix %s\n' "$*" >>"$TEST_LOG"
if [[ "$*" == *'eval --raw'* ]]; then printf '%s' "$TEST_CONFIGURED_USER"; fi
EOF
  cat >"$BATS_TEST_TMPDIR/bin/id" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == '-un' ]] || exit 2
printf '%s\n' "$TEST_CURRENT_USER"
EOF
  cat >"$BATS_TEST_TMPDIR/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"$TEST_LOG"
printf '%s' "${NIX_CONFIG:-}" >"$TEST_CONFIG_LOG"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
}

@test "WSL rebuild preserves an already declared custom user" {
  export TEST_CURRENT_USER=alice TEST_CONFIGURED_USER=alice
  run "$REPO_ROOT/scripts/sh/install-nixos.sh"
  [ "$status" -eq 0 ]
  grep -q 'sudo nixos-rebuild switch' "$TEST_LOG"
}

@test "WSL username changes require boot and restart before switch" {
  export TEST_CURRENT_USER=alice
  run "$REPO_ROOT/scripts/sh/install-nixos.sh"
  [ "$status" -ne 0 ]
  [[ $output == *'nixos-rebuild boot'* ]]
  ! grep -q 'sudo\|flake update' "$TEST_LOG"
}

@test "native Linux rebuild does not require WSL account discovery" {
  export TEST_KERNEL=Linux
  run "$REPO_ROOT/scripts/sh/install-nixos.sh"
  [ "$status" -eq 0 ]
  grep -q 'sudo nixos-rebuild switch' "$TEST_LOG"
  ! grep -q 'eval --raw' "$TEST_LOG"
}

@test "frozen NixOS deployment preserves the target and disables local and remote compilation under sudo" {
  export TEST_KERNEL=Linux
  run env UPDATE_FLAKE_INPUTS=false DOTFILES_ALLOW_BUILDS=false \
    DOTFILES_FLAKE_REF=path:/nix/store/prepared-flake#linux \
    "$REPO_ROOT/scripts/sh/install-nixos.sh"
  [ "$status" -eq 0 ]
  run grep -q 'flake update' "$TEST_LOG"
  [ "$status" -eq 1 ]
  grep -Fq 'sudo --preserve-env=NIX_CONFIG nixos-rebuild switch --flake path:/nix/store/prepared-flake#linux' "$TEST_LOG"
  grep -Fq -- '--no-update-lock-file' "$TEST_LOG"
  grep -Fxq 'max-jobs = 0' "$TEST_CONFIG_LOG"
  grep -Fxq 'builders =' "$TEST_CONFIG_LOG"
  grep -Fxq 'fallback = false' "$TEST_CONFIG_LOG"
}

@test "WSL account discovery uses the selected deployment target" {
  run env UPDATE_FLAKE_INPUTS=false DOTFILES_FLAKE_REF=path:/nix/store/prepared-flake#staged \
    "$REPO_ROOT/scripts/sh/install-nixos.sh"
  [ "$status" -eq 0 ]
  grep -Fq 'eval --raw path:/nix/store/prepared-flake#nixosConfigurations.staged.config.wsl.defaultUser' "$TEST_LOG"
  grep -Fq -- '--flake path:/nix/store/prepared-flake#staged' "$TEST_LOG"
  run grep -q 'flake update' "$TEST_LOG"
  [ "$status" -eq 1 ]
}
