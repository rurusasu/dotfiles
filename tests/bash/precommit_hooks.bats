#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	TEST_BIN="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$TEST_BIN"
}

write_uname_stub() {
	local system_name="$1"
	cat >"$TEST_BIN/uname" <<EOF
#!/usr/bin/env bash
printf '%s\n' '$system_name'
EOF
	chmod +x "$TEST_BIN/uname"
}

write_pwsh_stub() {
	cat >"$TEST_BIN/pwsh.exe" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$PWSH_CALL_LOG"
exit "${PWSH_EXIT_CODE:-0}"
EOF
	chmod +x "$TEST_BIN/pwsh.exe"
}

@test "PowerShell pre-commit runner skips macOS" {
	write_uname_stub Darwin
	write_pwsh_stub
	export PWSH_CALL_LOG="$BATS_TEST_TMPDIR/pwsh.log"

	PATH="$TEST_BIN:$PATH" run "$REPO_ROOT/scripts/sh/run-windows-powershell-tests.sh" -NoProfile -Command "exit 1"

	[ "$status" -eq 0 ]
	[ ! -e "$PWSH_CALL_LOG" ]
}

@test "PowerShell pre-commit runner delegates to pwsh.exe on Windows Git Bash" {
	write_uname_stub MINGW64_NT-10.0
	write_pwsh_stub
	export PWSH_CALL_LOG="$BATS_TEST_TMPDIR/pwsh.log"
	export PWSH_EXIT_CODE=23

	PATH="$TEST_BIN:$PATH" run "$REPO_ROOT/scripts/sh/run-windows-powershell-tests.sh" -NoProfile -Command "Write-Host ok"

	[ "$status" -eq 23 ]
	grep -q -- '-NoProfile -Command Write-Host ok' "$PWSH_CALL_LOG"
}

@test "PowerShell pre-commit hooks use the platform-aware runner" {
	run grep -c 'scripts/sh/run-windows-powershell-tests.sh' "$REPO_ROOT/.pre-commit-config.yaml"

	[ "$status" -eq 0 ]
	[ "$output" -eq 2 ]
}
