#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	WRAPPER="$REPO_ROOT/nix/modules/1password/op-ssh-sign-wsl"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	BUFFER="$BATS_TEST_TMPDIR/signing buffer"
	WSLPATH_ARGS="$BATS_TEST_TMPDIR/wslpath-args"
	SIGNER_ARGS="$BATS_TEST_TMPDIR/signer-args"
	SIGNER_STDIN="$BATS_TEST_TMPDIR/signer-stdin"
	mkdir -p "$STUB_BIN"
	printf '%s\0%s\n' payload binary >"$BUFFER"
	export WSLPATH_ARGS SIGNER_ARGS SIGNER_STDIN
	export PATH="$STUB_BIN:$PATH"

	cat >"$STUB_BIN/wslpath" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$WSLPATH_ARGS"
[[ "$1" == -w ]]
printf 'WINDOWS:%s\n' "$2"
EOF
	cat >"$STUB_BIN/op-ssh-sign.exe" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$SIGNER_ARGS"
cat >"$SIGNER_STDIN"
printf 'signature fixture\n'
EOF
	chmod +x "$STUB_BIN/wslpath" "$STUB_BIN/op-ssh-sign.exe"
}

@test "resolves a Linux public-key symlink before translating the signer path" {
	key_directory="$BATS_TEST_TMPDIR/store key"
	key="$key_directory/public key.pub"
	key_link="$BATS_TEST_TMPDIR/signing_key.pub"
	mkdir -p "$key_directory"
	printf 'ssh-ed25519 public-key-fixture\n' >"$key"
	ln -s "$key" "$key_link"
	resolved_key="$(readlink -f "$key")"

	run bash "$WRAPPER" -Y sign -n git -f "$key_link" "$BUFFER"

	[ "$status" -eq 0 ]
	[ -z "$output" ]
	printf '%s\n' -w "$resolved_key" >"$BATS_TEST_TMPDIR/expected-wslpath-args"
	cmp "$BATS_TEST_TMPDIR/expected-wslpath-args" "$WSLPATH_ARGS"
	printf '%s\n' -Y sign -n git -f "WINDOWS:$resolved_key" >"$BATS_TEST_TMPDIR/expected-signer-args"
	cmp "$BATS_TEST_TMPDIR/expected-signer-args" "$SIGNER_ARGS"
	cmp "$BUFFER" "$SIGNER_STDIN"
	[ "$(cat "$BUFFER.sig")" = 'signature fixture' ]
}

@test "preserves Windows and mounted Windows public-key paths" {
	for key in 'C:\Users\fixture\.ssh\key.pub' '\\server\share\key.pub' '/mnt/c/Users/fixture/key.pub'; do
		run bash "$WRAPPER" -Y sign -n git -f "$key" "$BUFFER"

		[ "$status" -eq 0 ]
		[ ! -e "$WSLPATH_ARGS" ]
		printf '%s\n' -Y sign -n git -f "$key" >"$BATS_TEST_TMPDIR/expected-signer-args"
		cmp "$BATS_TEST_TMPDIR/expected-signer-args" "$SIGNER_ARGS"
		cmp "$BUFFER" "$SIGNER_STDIN"
		[ "$(cat "$BUFFER.sig")" = 'signature fixture' ]
	done
}
