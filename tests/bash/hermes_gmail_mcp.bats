#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export HOME="$BATS_TEST_TMPDIR/home"
}

@test "declares the official Google Gmail MCP endpoint and OAuth settings" {
	source_file="$REPO_ROOT/docker/hermes-agent/bootstrap/hermes_bootstrap/google_gmail.py"

	run grep -F 'https://gmailmcp.googleapis.com/mcp/v1' "$source_file"
	[ "$status" -eq 0 ]
	run grep -F '"auth": "oauth"' "$source_file"
	[ "$status" -eq 0 ]
	run grep -F 'https://www.googleapis.com/auth/gmail.readonly' "$source_file"
	[ "$status" -eq 0 ]
	run grep -F 'https://www.googleapis.com/auth/gmail.compose' "$source_file"
	[ "$status" -eq 0 ]
}

@test "declares exactly the read and draft Gmail tool allowlist" {
	source_file="$REPO_ROOT/docker/hermes-agent/bootstrap/hermes_bootstrap/google_gmail.py"

	for tool in search_threads get_thread get_message list_labels list_drafts create_draft; do
		run grep -F "\"$tool\"" "$source_file"
		[ "$status" -eq 0 ]
	done

	for forbidden in send_message delete_message modify_label create_label delete_label update_label; do
		run grep -F "\"$forbidden\"" "$source_file"
		[ "$status" -eq 1 ]
	done
}
