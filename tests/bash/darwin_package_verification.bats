#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
	VERIFIER="$REPO_ROOT/scripts/sh/verify-darwin-package.sh"
	BASH_32="/bin/bash"
	TEST_BIN="$BATS_TEST_TMPDIR/bin"
	COMMAND_LOG="$BATS_TEST_TMPDIR/commands.log"
	SUPPORT_REPORT="$BATS_TEST_TMPDIR/report"
	SUPPORT_JSON="$SUPPORT_REPORT/support.json"
	STORE_PATH="$BATS_TEST_TMPDIR/store"
	APP_PATH="$STORE_PATH/Applications/Test App.app"
	REAL_JQ="$(command -v jq)"

	mkdir -p \
		"$TEST_BIN" \
		"$SUPPORT_REPORT" \
		"$APP_PATH/Contents/MacOS" \
		"$STORE_PATH/bin"
	: >"$COMMAND_LOG"
	: >"$APP_PATH/Contents/Info.plist"
	: >"$APP_PATH/Contents/MacOS/Test App"
	chmod +x "$APP_PATH/Contents/MacOS/Test App"

	cat >"$SUPPORT_JSON" <<'JSON'
{
  "test-app": {
    "darwin": {
      "provider": "nix",
      "source": "nixpkgs",
      "nixAttr": "test-app",
      "identity": {
        "appName": "Test App.app",
        "bundleId": "com.example.test-app",
        "executable": "Test App"
      }
    },
    "installFeature": null
  },
  "test-command": {
    "darwin": {
      "provider": "nix",
      "source": "nixpkgs",
      "nixAttr": "test-command",
      "identity": {
        "command": "test-command",
        "versionArgs": ["version", "--json"]
      }
    },
    "installFeature": null
  },
  "nix-adhoc-app": {
    "darwin": {
      "provider": "nix",
      "source": "nixpkgs",
      "nixAttr": "nix-adhoc-app",
      "identity": {
        "appName": "Test App.app",
        "bundleId": "com.example.test-app",
        "executable": "Test App"
      }
    },
    "installFeature": null
  },
  "_1password-cli": {
    "darwin": {
      "provider": "nix",
      "source": "nixpkgs",
      "nixAttr": "_1password-cli",
      "identity": {
        "command": "op",
        "versionArgs": ["--version"]
      }
    },
    "installFeature": null
  },
  "traversal-app-name": {
    "darwin": {
      "provider": "nix",
      "source": "nixpkgs",
      "nixAttr": "traversal-app-name",
      "identity": {
        "appName": "../Outside.app",
        "bundleId": "com.example.outside",
        "executable": "Outside"
      }
    },
    "installFeature": null
  },
  "traversal-app-executable": {
    "darwin": {
      "provider": "nix",
      "source": "nixpkgs",
      "nixAttr": "traversal-app-executable",
      "identity": {
        "appName": "Test App.app",
        "bundleId": "com.example.test-app",
        "executable": "../Outside"
      }
    },
    "installFeature": null
  },
  "traversal-command": {
    "darwin": {
      "provider": "nix",
      "source": "nixpkgs",
      "nixAttr": "traversal-command",
      "identity": {
        "command": "..",
        "versionArgs": ["--version"]
      }
    },
    "installFeature": null
  },
  "flat-only-app": {
    "darwin": {
      "provider": "nix",
      "source": "nixpkgs",
      "identity": "flat-only-app",
      "nixAttr": "flat-only-app",
      "appName": "Test App.app",
      "bundleId": "com.example.test-app",
      "executable": "Test App"
    },
    "installFeature": null
  }
}
JSON

	write_stub jq 'exec "$REAL_JQ" "$@"'
	write_stub plistbuddy '
log_command plistbuddy "$@"
case "${2:-}" in
  "Print :CFBundleIdentifier") printf "%s\n" "${ACTUAL_BUNDLE_ID:-com.example.test-app}" ;;
  "Print :CFBundleExecutable") printf "%s\n" "${ACTUAL_EXECUTABLE:-Test App}" ;;
  *) exit 2 ;;
esac
'
write_stub codesign '
log_command codesign "$@"
if [[ ${CODESIGN_ADHOC:-0} == 1 && " $* " == *" --display "* ]]; then
  printf "Signature=adhoc\\n"
fi
'
	write_stub spctl 'log_command spctl "$@"'
	write_stub open 'log_command open "$@"'
	write_stub test-command 'log_command test-command "$@"'
	cp "$TEST_BIN/test-command" "$STORE_PATH/bin/test-command"
	cp "$TEST_BIN/test-command" "$STORE_PATH/bin/op"

	export COMMAND_LOG REAL_JQ SUPPORT_REPORT STORE_PATH
	export DOTFILES_JQ_COMMAND="$TEST_BIN/jq"
	export DOTFILES_PLISTBUDDY_COMMAND="$TEST_BIN/plistbuddy"
	export DOTFILES_CODESIGN_COMMAND="$TEST_BIN/codesign"
	export DOTFILES_SPCTL_COMMAND="$TEST_BIN/spctl"
	export DOTFILES_OPEN_COMMAND="$TEST_BIN/open"
	export CODESIGN_ADHOC=0
}

write_stub() {
	local name="$1" body="$2"
	cat >"$TEST_BIN/$name" <<EOF
#!/usr/bin/env bash
set -euo pipefail
log_command() {
  local command="\$1"
  shift
  printf '%s' "\$command" >>"\$COMMAND_LOG"
  printf ' <%s>' "\$@" >>"\$COMMAND_LOG"
  printf '\n' >>"\$COMMAND_LOG"
}
$body
EOF
	chmod +x "$TEST_BIN/$name"
}

assert_log_order() {
	local previous=0 expected line
	for expected in "$@"; do
		line="$(grep -nFx "$expected" "$COMMAND_LOG" | head -1 | cut -d: -f1)"
		[ -n "$line" ]
		[ "$line" -gt "$previous" ]
		previous="$line"
	done
}

@test "mismatched bundle ID exits before codesign" {
	export ACTUAL_BUNDLE_ID="com.example.wrong"

	run "$BASH_32" "$VERIFIER" \
		--support-json "$SUPPORT_JSON" \
		--id test-app \
		--store-path "$STORE_PATH"

	[ "$status" -ne 0 ]
	[[ "$output" == *"CFBundleIdentifier mismatch"* ]]
	grep -Fqx "plistbuddy <-c> <Print :CFBundleIdentifier> <$APP_PATH/Contents/Info.plist>" "$COMMAND_LOG"
	! grep -q '^codesign ' "$COMMAND_LOG"
}

@test "valid app verifies metadata and signatures before opening its exact Nix path" {
	run "$BASH_32" "$VERIFIER" \
		--support-json "$SUPPORT_JSON" \
		--id test-app \
		--store-path "$STORE_PATH" \
		--launch

	[ "$status" -eq 0 ]
	assert_log_order \
		"plistbuddy <-c> <Print :CFBundleIdentifier> <$APP_PATH/Contents/Info.plist>" \
		"plistbuddy <-c> <Print :CFBundleExecutable> <$APP_PATH/Contents/Info.plist>" \
		"codesign <--verify> <--deep> <--strict> <$APP_PATH>" \
		"spctl <--assess> <--type> <execute> <$APP_PATH>" \
		"open <$APP_PATH>"
}

@test "Nixpkgs ad-hoc app signatures skip Gatekeeper after codesign verification" {
	export CODESIGN_ADHOC=1

	run "$BASH_32" "$VERIFIER" \
		--support-json "$SUPPORT_JSON" \
		--id nix-adhoc-app \
		--store-path "$STORE_PATH"

	[ "$status" -eq 0 ]
	grep -Fq "codesign <--verify> <--deep> <--strict> <$APP_PATH>" "$COMMAND_LOG"
	grep -Fq 'codesign <--display> <--verbose=4' "$COMMAND_LOG"
	! grep -q '^spctl ' "$COMMAND_LOG"
}

@test "command identity runs the declared version arguments" {
	run "$BASH_32" "$VERIFIER" \
		--support-json "$SUPPORT_JSON" \
		--id test-command \
		--store-path "$STORE_PATH"

	[ "$status" -eq 0 ]
	grep -Fqx "test-command <version> <--json>" "$COMMAND_LOG"
	! grep -q '^plistbuddy ' "$COMMAND_LOG"
}

@test "catalog IDs may start with an underscore" {
	run "$BASH_32" "$VERIFIER" --support-json "$SUPPORT_JSON" --id _1password-cli --store-path "$STORE_PATH"

	[ "$status" -eq 0 ]
	[[ "$output" != *"invalid catalog ID"* ]]
	grep -Fqx 'test-command <--version>' "$COMMAND_LOG"
}

@test "flat-only verification metadata is rejected instead of bypassing nested identity" {
	run "$BASH_32" "$VERIFIER" \
		--support-json "$SUPPORT_JSON" \
		--id flat-only-app \
		--store-path "$STORE_PATH"

	[ "$status" -ne 0 ]
	[[ "$output" == *"Darwin verification identity is missing for flat-only-app"* ]]
	[ ! -s "$COMMAND_LOG" ]
}

@test "appName traversal is rejected before inspecting an app" {
	run "$BASH_32" "$VERIFIER" \
		--support-json "$SUPPORT_JSON" \
		--id traversal-app-name \
		--store-path "$STORE_PATH"

	[ "$status" -ne 0 ]
	[[ "$output" == *"appName must be a single path component"* ]]
	[ ! -s "$COMMAND_LOG" ]
}

@test "app executable traversal is rejected before inspecting its path" {
	run "$BASH_32" "$VERIFIER" \
		--support-json "$SUPPORT_JSON" \
		--id traversal-app-executable \
		--store-path "$STORE_PATH"

	[ "$status" -ne 0 ]
	[[ "$output" == *"executable must be a single path component"* ]]
	[ ! -s "$COMMAND_LOG" ]
}

@test "command traversal is rejected before executing outside the store bin directory" {
	run "$BASH_32" "$VERIFIER" \
		--support-json "$SUPPORT_JSON" \
		--id traversal-command \
		--store-path "$STORE_PATH"

	[ "$status" -ne 0 ]
	[[ "$output" == *"command must be a single path component"* ]]
	[ ! -s "$COMMAND_LOG" ]
}
