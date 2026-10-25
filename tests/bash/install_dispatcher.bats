#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	TEST_BIN="$BATS_TEST_TMPDIR/bin"
	DISPATCH_LOG="$BATS_TEST_TMPDIR/dispatch.log"
	TEST_CHECKOUT="$BATS_TEST_TMPDIR/home/.dotfiles"
	TEST_NIX_DAEMON_PROFILE="$BATS_TEST_TMPDIR/nix-daemon.sh"
	TEST_NIX_PROFILE_FIXTURE="$BATS_TEST_TMPDIR/nix-daemon-fixture.sh"
	TEST_NIX_BIN="$BATS_TEST_TMPDIR/nix-bin"
	mkdir -p "$TEST_BIN" "$TEST_NIX_BIN" "${TEST_CHECKOUT%/*}"
	export PATH="$TEST_BIN:/usr/bin:/bin"
	export DISPATCH_LOG TEST_NIX_DAEMON_PROFILE TEST_NIX_PROFILE_FIXTURE TEST_NIX_BIN
	cat >"$TEST_BIN/nix" <<'EOF'
#!/usr/bin/env bash
printf 'nix=%s\n' "$*" >>"$DISPATCH_LOG"
EOF
	chmod +x "$TEST_BIN/nix"
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
	sed -e "s|/etc/NIXOS|$BATS_TEST_TMPDIR/NIXOS|g" \
		-e "s|\$HOME/.dotfiles|$TEST_CHECKOUT|g" \
		-e "s|/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh|$TEST_NIX_DAEMON_PROFILE|g" \
		-e "s|\$HOME/.nix-profile/etc/profile.d/nix.sh|$BATS_TEST_TMPDIR/nix.sh|g" \
		"$REPO_ROOT/install.sh" >"$BATS_TEST_TMPDIR/repo/install.sh"
	chmod +x "$BATS_TEST_TMPDIR/repo/install.sh"
	for installer in install-macos.sh install-nixos.sh; do
		cat >"$BATS_TEST_TMPDIR/repo/scripts/sh/$installer" <<'EOF'
#!/usr/bin/env bash
printf 'target=%s args=%s\n' "${0##*/}" "$*" >"$DISPATCH_LOG"
EOF
		chmod +x "$BATS_TEST_TMPDIR/repo/scripts/sh/$installer"
	done
}

write_nix_profile_fixture() {
	mv "$TEST_BIN/nix" "$TEST_NIX_BIN/nix"
	cat >"$TEST_NIX_PROFILE_FIXTURE" <<'EOF'
# Nix profiles probe optional shell variables without requiring them to be set.
if [ -n "$ZSH_VERSION" ]; then
	:
fi
export PATH="$TEST_NIX_BIN:$PATH"
EOF
}

run_installer_checking_nounset() {
	run env -u ZSH_VERSION bash -c '
exec() {
	case "$-" in
		*u*) ;;
		*) printf "nounset was not restored before dispatch\n" >&2; return 91 ;;
	esac
	builtin exec "$@"
}
test_installer=$1
shift
source "$test_installer"
' bash "$BATS_TEST_TMPDIR/repo/install.sh" --example
}

@test "Darwin arm64 dispatches to the macOS installer with arguments intact" {
	write_uname_stub
	write_dispatch_repo
	export TEST_UNAME_S=Darwin TEST_UNAME_M=arm64

	run "$BATS_TEST_TMPDIR/repo/install.sh" --example

	[ "$status" -eq 0 ]
	grep -q '^target=install-macos.sh args=--example$' "$DISPATCH_LOG"
	[[ "$TEST_CHECKOUT" -ef "$BATS_TEST_TMPDIR/repo" ]]
}

@test "macOS activates a newly installed Nix profile with optional shell variables unset" {
	write_uname_stub
	write_dispatch_repo
	write_nix_profile_fixture
	export TEST_UNAME_S=Darwin TEST_UNAME_M=arm64
	cat >"$TEST_BIN/curl" <<'EOF'
#!/usr/bin/env bash
cat <<'INSTALLER'
cp "$TEST_NIX_PROFILE_FIXTURE" "$TEST_NIX_DAEMON_PROFILE"
INSTALLER
EOF
	chmod +x "$TEST_BIN/curl"

	run_installer_checking_nounset

	[ "$status" -eq 0 ]
	[ -f "$TEST_NIX_DAEMON_PROFILE" ]
	grep -q '^target=install-macos.sh args=--example$' "$DISPATCH_LOG"
}

@test "macOS activates an existing Nix profile when nix is missing from PATH" {
	write_uname_stub
	write_dispatch_repo
	write_nix_profile_fixture
	cp "$TEST_NIX_PROFILE_FIXTURE" "$TEST_NIX_DAEMON_PROFILE"
	export TEST_UNAME_S=Darwin TEST_UNAME_M=arm64
	cat >"$TEST_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf 'unexpected installer download\n' >&2
exit 92
EOF
	chmod +x "$TEST_BIN/curl"

	run_installer_checking_nounset

	[ "$status" -eq 0 ]
	grep -q '^target=install-macos.sh args=--example$' "$DISPATCH_LOG"
}

@test "Linux bootstraps with the Lix installer and activates its profile" {
	write_uname_stub
	write_dispatch_repo
	write_nix_profile_fixture
	export TEST_UNAME_S=Linux TEST_UNAME_M=x86_64
	cat >"$TEST_BIN/curl" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == '-fsSL https://install.lix.systems/lix' ]] || exit 93
cat <<'INSTALLER'
[ "$*" = 'install --no-confirm' ] || exit 94
cp "$TEST_NIX_PROFILE_FIXTURE" "$TEST_NIX_DAEMON_PROFILE"
INSTALLER
EOF
	chmod +x "$TEST_BIN/curl"

	run_installer_checking_nounset

	[ "$status" -eq 0 ]
	[ -f "$TEST_NIX_DAEMON_PROFILE" ]
	grep -q 'home-manager -- switch' "$DISPATCH_LOG"
}

@test "NixOS dispatches to the native installer" {
	write_uname_stub
	write_dispatch_repo
	marker="$BATS_TEST_TMPDIR/NIXOS"
	touch "$marker"
	export TEST_UNAME_S=Linux TEST_UNAME_M=x86_64

	run "$BATS_TEST_TMPDIR/repo/install.sh" --example

	[ "$status" -eq 0 ]
	grep -q '^target=install-nixos.sh args=--example$' "$DISPATCH_LOG"
}

@test "non-NixOS Linux updates inputs then runs Home Manager with arguments intact" {
	write_uname_stub
	write_dispatch_repo
	local dispatch_root
	dispatch_root="$(cd "$BATS_TEST_TMPDIR/repo" && pwd -P)"
	export TEST_UNAME_S=Linux TEST_UNAME_M=x86_64

	for distribution in ubuntu debian fedora; do
		release_file="$BATS_TEST_TMPDIR/$distribution-os-release"
		printf 'ID=%s\n' "$distribution" >"$release_file"
		export DOTFILES_OS_RELEASE_FILE="$release_file"
		: >"$DISPATCH_LOG"

		run "$BATS_TEST_TMPDIR/repo/install.sh" --example

		[ "$status" -eq 0 ]
		[[ "$TEST_CHECKOUT" -ef "$BATS_TEST_TMPDIR/repo" ]]
		[ "$(sed -n '1p' "$DISPATCH_LOG")" = "nix=--accept-flake-config --extra-experimental-features nix-command flakes flake update --flake $dispatch_root" ]
		[ "$(sed -n '2p' "$DISPATCH_LOG")" = "nix=--accept-flake-config --extra-experimental-features nix-command flakes run $dispatch_root#home-manager -- switch --flake $dispatch_root#x86_64-linux --impure --example" ]
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
	[[ "$output" == *"Unsupported platform"* ]]
}
