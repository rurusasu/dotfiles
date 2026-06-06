#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	STUB_BIN="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$TEST_HOME" "$STUB_BIN"

	write_stub tmux 'exit 0'
	write_stub curl 'exit 0'
	write_stub git 'exit 0'
	write_stub tar 'exit 0'
	write_stub dpkg 'exit 0'
	write_stub apt-get 'exit 0'
	write_stub sudo 'exec "$@"'
	write_stub chezmoi 'echo "chezmoi stub"; exit 0'
	write_stub claude 'echo "claude stub"; exit 0'
	write_stub npm 'echo "npm stub"; exit 0'
	write_stub nvim 'if [ "${1:-}" = "--version" ]; then echo "NVIM v0.10.0"; exit 0; fi; exit 0'
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

@test "bootstrap.sh reaches completion without hanging when installers are stubbed" {
	export HOME="$TEST_HOME"
	export PATH="$STUB_BIN:$PATH"

	run timeout 30 bash "$REPO_ROOT/bootstrap.sh" 2>&1

	[ "$status" -eq 0 ]
	[[ "$output" == *"bootstrap complete"* ]]
}
