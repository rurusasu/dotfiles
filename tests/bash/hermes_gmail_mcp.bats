#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	export HOME="$BATS_TEST_TMPDIR/home"
}

@test "declares the shared local Gmail MCP command and credentials" {
	source_file="$REPO_ROOT/docker/hermes-agent/bootstrap/hermes_bootstrap/google_gmail.py"

	run grep -F '"command": "gmail-mcp"' "$source_file"
	[ "$status" -eq 0 ]
	run grep -F 'GMAIL_OAUTH_PATH' "$source_file"
	[ "$status" -eq 0 ]
	run grep -F 'GMAIL_CREDENTIALS_PATH' "$source_file"
	[ "$status" -eq 0 ]
	run grep -F 'gmailmcp.googleapis.com' "$source_file"
	[ "$status" -eq 1 ]
}

@test "pins the local stdio Gmail MCP package in the Hermes image" {
	dockerfile="$REPO_ROOT/docker/hermes-agent/Dockerfile"
	run grep -F 'ARG GOOGLE_GMAIL_MCP_VERSION=1.2.3' "$dockerfile"
	[ "$status" -eq 0 ]
	run grep -F '"@artymclabin/gmail-mcp@${GOOGLE_GMAIL_MCP_VERSION}"' "$dockerfile"
	[ "$status" -eq 0 ]
}

@test "declares exactly the read and draft Gmail tool allowlist" {
	source_file="$REPO_ROOT/docker/hermes-agent/bootstrap/hermes_bootstrap/google_gmail.py"

	for tool in search_emails read_email get_thread list_inbox_threads get_inbox_with_threads list_email_labels draft_email; do
		run grep -F "\"$tool\"" "$source_file"
		[ "$status" -eq 0 ]
	done

	for forbidden in send_email delete_email modify_email create_label delete_label update_label; do
		run grep -F "\"$forbidden\"" "$source_file"
		[ "$status" -eq 1 ]
	done
}
