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

write_dispatch_repo() {
	mkdir -p "$BATS_TEST_TMPDIR/repo/scripts/sh"
	cp "$REPO_ROOT/install.sh" "$BATS_TEST_TMPDIR/repo/install.sh"
	for installer in install-macos.sh install-nixos.sh install-home-manager.sh; do
		cat >"$BATS_TEST_TMPDIR/repo/scripts/sh/$installer" <<'EOF'
#!/usr/bin/env bash
printf 'target=%s args=%s\n' "${0##*/}" "$*" >"$DISPATCH_LOG"
EOF
		chmod +x "$BATS_TEST_TMPDIR/repo/scripts/sh/$installer"
	done
}

@test "Darwin arm64 dispatches to the macOS installer with arguments intact" {
	write_uname_stub
	write_dispatch_repo
	export TEST_UNAME_S=Darwin TEST_UNAME_M=arm64

	run "$BATS_TEST_TMPDIR/repo/install.sh" --example

	[ "$status" -eq 0 ]
	grep -q '^target=install-macos.sh args=--example$' "$DISPATCH_LOG"
}

@test "NixOS dispatches to the native installer" {
	write_uname_stub
	write_dispatch_repo
	marker="$BATS_TEST_TMPDIR/NIXOS"
	touch "$marker"
	export TEST_UNAME_S=Linux TEST_UNAME_M=x86_64
	export DOTFILES_NIXOS_MARKER="$marker"

	run "$BATS_TEST_TMPDIR/repo/install.sh" --example

	[ "$status" -eq 0 ]
	grep -q '^target=install-nixos.sh args=--example$' "$DISPATCH_LOG"
}

@test "non-NixOS Linux dispatches to Home Manager with arguments intact" {
	write_uname_stub
	write_dispatch_repo
	export TEST_UNAME_S=Linux TEST_UNAME_M=x86_64
	export DOTFILES_NIXOS_MARKER="$BATS_TEST_TMPDIR/not-nixos"

	for distribution in ubuntu debian fedora; do
		release_file="$BATS_TEST_TMPDIR/$distribution-os-release"
		printf 'ID=%s\n' "$distribution" >"$release_file"
		export DOTFILES_OS_RELEASE_FILE="$release_file"

		run "$BATS_TEST_TMPDIR/repo/install.sh" --example

		[ "$status" -eq 0 ]
		grep -q '^target=install-home-manager.sh args=--example$' "$DISPATCH_LOG"
	done
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
