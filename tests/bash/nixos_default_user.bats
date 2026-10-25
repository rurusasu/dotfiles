#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	mkdir -p "$BATS_TEST_TMPDIR/bin"
	export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
	export TEST_LOG="$BATS_TEST_TMPDIR/commands"
	export TEST_KERNEL=Microsoft TEST_CURRENT_USER=nixos TEST_CURRENT_UID=1000 TEST_CONFIGURED_USER=nixos
	cat >"$BATS_TEST_TMPDIR/bin/uname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$TEST_KERNEL"
EOF
	cat >"$BATS_TEST_TMPDIR/bin/nix" <<'EOF'
#!/usr/bin/env bash
printf 'nix %s\n' "$*" >>"$TEST_LOG"
if [[ "$*" == *'eval --raw'* ]]; then printf '%s' "$TEST_CONFIGURED_USER"; fi
EOF
	cat >"$BATS_TEST_TMPDIR/bin/getent" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == "passwd $TEST_CURRENT_UID" ]] || exit 2
printf '%s:x:%s:100:/home/%s:/bin/bash\n' "$TEST_CURRENT_USER" "$TEST_CURRENT_UID" "$TEST_CURRENT_USER"
EOF
	cat >"$BATS_TEST_TMPDIR/bin/id" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == '-un' ]] || exit 2
printf '%s\n' "$TEST_CURRENT_USER"
EOF
	cat >"$BATS_TEST_TMPDIR/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"$TEST_LOG"
EOF
	chmod +x "$BATS_TEST_TMPDIR/bin/"*
}

@test "WSL rebuild preserves an already declared custom user" {
	export TEST_CURRENT_USER=alice TEST_CONFIGURED_USER=alice
	run "$REPO_ROOT/scripts/sh/install-nixos.sh"
	[ "$status" -eq 0 ]
	grep -q 'sudo nixos-rebuild switch' "$TEST_LOG"
}

@test "WSL rebuild accepts a configured current user whose UID is not 1000" {
	export TEST_CURRENT_USER=alice TEST_CURRENT_UID=2000 TEST_CONFIGURED_USER=alice
	run "$REPO_ROOT/scripts/sh/install-nixos.sh"
	[ "$status" -eq 0 ]
	grep -q 'sudo nixos-rebuild switch' "$TEST_LOG"
}

@test "WSL username changes require boot and restart before switch" {
	export TEST_CURRENT_USER=alice
	run "$REPO_ROOT/scripts/sh/install-nixos.sh"
	[ "$status" -ne 0 ]
	[[ "$output" == *'nixos-rebuild boot'* ]]
	! grep -q 'sudo\|flake update' "$TEST_LOG"
}

@test "native Linux rebuild does not require WSL account discovery" {
	export TEST_KERNEL=Linux
	run "$REPO_ROOT/scripts/sh/install-nixos.sh"
	[ "$status" -eq 0 ]
	grep -q 'sudo nixos-rebuild switch' "$TEST_LOG"
	! grep -q 'eval --raw' "$TEST_LOG"
}
