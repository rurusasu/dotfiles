#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	TEST_BIN="$BATS_TEST_TMPDIR/bin"
	DISPATCH_LOG="$BATS_TEST_TMPDIR/dispatch.log"
	mkdir -p "$TEST_BIN"
	export PATH="$TEST_BIN:/usr/bin:/bin"
	export DISPATCH_LOG
}

write_uname_stub() {
	cat >"$TEST_BIN/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
	-s) printf '%s\n' "${TEST_UNAME_S}" ;;
	-m) printf '%s\n' "${TEST_UNAME_M}" ;;
	*) exit 2 ;;
esac
EOF
	chmod +x "$TEST_BIN/uname"
}

write_macos_installer_stub() {
	mkdir -p "$BATS_TEST_TMPDIR/repo/scripts/sh"
	cp "$REPO_ROOT/install.sh" "$BATS_TEST_TMPDIR/repo/install.sh"
	cat >"$BATS_TEST_TMPDIR/repo/scripts/sh/install-macos.sh" <<'EOF'
#!/usr/bin/env bash
printf 'args=%s\n' "$*" >"$DISPATCH_LOG"
EOF
	chmod +x "$BATS_TEST_TMPDIR/repo/scripts/sh/install-macos.sh"
}

@test "Darwin arm64 dispatches to the macOS installer with arguments intact" {
	write_uname_stub
	write_macos_installer_stub
	export TEST_UNAME_S=Darwin TEST_UNAME_M=arm64

	run "$BATS_TEST_TMPDIR/repo/install.sh" --example

	[ "$status" -eq 0 ]
	grep -q '^args=--example$' "$DISPATCH_LOG"
}

@test "Windows-like environments direct the user to install.cmd" {
	write_uname_stub
	export TEST_UNAME_S=MINGW64_NT TEST_UNAME_M=x86_64

	run "$REPO_ROOT/install.sh"

	[ "$status" -ne 0 ]
	[[ "$output" == *"install.cmd"* ]]
}

@test "Intel macOS is rejected explicitly" {
	write_uname_stub
	export TEST_UNAME_S=Darwin TEST_UNAME_M=x86_64

	run "$REPO_ROOT/install.sh"

	[ "$status" -ne 0 ]
	[[ "$output" == *"Apple Silicon"* ]]
}
