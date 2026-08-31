#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
	VERIFIER="$REPO_ROOT/scripts/sh/verify-darwin-package.sh"
	MIGRATOR="$REPO_ROOT/scripts/sh/migrate-darwin-provider.sh"
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
    "installFeature": null,
    "legacyDarwin": null
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
    "installFeature": null,
    "legacyDarwin": null
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
    "installFeature": null,
    "legacyDarwin": null
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
    "installFeature": null,
    "legacyDarwin": null
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
    "installFeature": null,
    "legacyDarwin": null
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
    "installFeature": null,
    "legacyDarwin": null
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
    "installFeature": null,
    "legacyDarwin": null
  },
  "legacy-app": {
    "darwin": {
      "provider": "nix",
      "source": "nixpkgs",
      "nixAttr": "legacy-app",
      "identity": {
        "appName": "Test App.app",
        "bundleId": "com.example.test-app",
        "executable": "Test App"
      }
    },
    "installFeature": "WithHermes",
    "legacyDarwin": {
      "provider": "homebrew-cask",
      "name": "legacy-app"
    }
  },
  "legacy-option": {
    "darwin": {
      "provider": "nix",
      "source": "nixpkgs",
      "nixAttr": "legacy-option",
      "identity": {
        "command": "test-command",
        "versionArgs": ["version"]
      }
    },
    "installFeature": null,
    "legacyDarwin": {
      "provider": "homebrew-cask",
      "name": "--zap"
    }
  },
  "legacy-formula": {
    "darwin": {
      "provider": "nix",
      "source": "nixpkgs",
      "nixAttr": "legacy-formula",
      "identity": {
        "command": "test-command",
        "versionArgs": ["version"]
      }
    },
    "installFeature": null,
    "legacyDarwin": {
      "provider": "homebrew-formula",
      "name": "owner/tools/legacy-formula"
    }
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
    "installFeature": null,
    "legacyDarwin": null
  }
}
JSON
	printf '["legacy-app"]\n' >"$SUPPORT_REPORT/darwin-packages.json"

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
	write_stub brew '
log_command brew "$@"
if [[ ${1:-} == list ]]; then
  exit "${BREW_LIST_STATUS:-0}"
fi
'
	write_stub verify '
log_command verify "$@"
exit "${VERIFY_STATUS:-0}"
'
	write_stub nix '
log_command nix "$@"
case " $* " in
  *" .#package-support-report "*) printf "%s\n" "$SUPPORT_REPORT" ;;
  *" .#darwin-legacy-app "*) printf "%s\n" "$STORE_PATH" ;;
  *) exit 2 ;;
esac
'
	write_stub test-command 'log_command test-command "$@"'
	cp "$TEST_BIN/test-command" "$STORE_PATH/bin/test-command"

	export COMMAND_LOG REAL_JQ SUPPORT_REPORT STORE_PATH
	export DOTFILES_JQ_COMMAND="$TEST_BIN/jq"
	export DOTFILES_PLISTBUDDY_COMMAND="$TEST_BIN/plistbuddy"
	export DOTFILES_CODESIGN_COMMAND="$TEST_BIN/codesign"
	export DOTFILES_SPCTL_COMMAND="$TEST_BIN/spctl"
	export DOTFILES_OPEN_COMMAND="$TEST_BIN/open"
	export DOTFILES_NIX_COMMAND="$TEST_BIN/nix"
	export DOTFILES_BREW_COMMAND="$TEST_BIN/brew"
	export DOTFILES_DARWIN_VERIFY_COMMAND="$TEST_BIN/verify"
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
	run "$BASH_32" "$MIGRATOR" --id _1password-cli

	[ "$status" -eq 0 ]
	[[ "$output" != *"invalid catalog ID"* ]]
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

@test "verification failure leaves the legacy cask installed" {
	export VERIFY_STATUS=42

	run "$BASH_32" "$MIGRATOR" --id legacy-app --feature WithHermes

	[ "$status" -eq 42 ]
	assert_log_order \
		"nix <build> <.#package-support-report> <--no-link> <--print-out-paths>" \
		"nix <build> <.#darwin-legacy-app> <--no-link> <--print-out-paths>" \
		"verify <--support-json> <$SUPPORT_JSON> <--id> <legacy-app> <--store-path> <$STORE_PATH>"
	! grep -q '^brew <uninstall>' "$COMMAND_LOG"
}

@test "successful verification removes the legacy cask without zap" {
	run "$BASH_32" "$MIGRATOR" --id legacy-app --feature WithHermes

	[ "$status" -eq 0 ]
	assert_log_order \
		"brew <list> <--cask> <--versions> <legacy-app>" \
		"verify <--support-json> <$SUPPORT_JSON> <--id> <legacy-app> <--store-path> <$STORE_PATH>" \
		"brew <uninstall> <--cask> <legacy-app>"
	! grep -q -- '--zap' "$COMMAND_LOG"
}

@test "missing legacy cask is an idempotent no-op before package realization" {
	export BREW_LIST_STATUS=1

	run "$BASH_32" "$MIGRATOR" --id legacy-app --feature WithHermes

	[ "$status" -eq 0 ]
	grep -Fqx "brew <list> <--cask> <--versions> <legacy-app>" "$COMMAND_LOG"
	! grep -q 'darwin-legacy-app' "$COMMAND_LOG"
	! grep -q '^verify ' "$COMMAND_LOG"
	! grep -q '^brew <uninstall>' "$COMMAND_LOG"
}

@test "missing legacy formula uses the formula installed check and exits cleanly" {
	export BREW_LIST_STATUS=1

	run "$BASH_32" "$MIGRATOR" --id legacy-formula

	[ "$status" -eq 0 ]
	grep -Fqx "brew <list> <--formula> <--versions> <owner/tools/legacy-formula>" "$COMMAND_LOG"
	! grep -q 'darwin-legacy-formula' "$COMMAND_LOG"
	! grep -q '^verify ' "$COMMAND_LOG"
	! grep -q '^brew <uninstall>' "$COMMAND_LOG"
}

@test "disabled install feature skips both package build and legacy removal" {
	run "$BASH_32" "$MIGRATOR" --all

	[ "$status" -eq 0 ]
	grep -Fqx "nix <build> <.#package-support-report> <--no-link> <--print-out-paths>" "$COMMAND_LOG"
	! grep -q 'darwin-legacy-app' "$COMMAND_LOG"
	! grep -q '^verify ' "$COMMAND_LOG"
	! grep -q '^brew ' "$COMMAND_LOG"
}

@test "legacy Homebrew token rejects option-like zap value before build or removal" {
	run "$BASH_32" "$MIGRATOR" --id legacy-option

	[ "$status" -ne 0 ]
	[[ "$output" == *"invalid legacy Homebrew token for legacy-option: --zap"* ]]
	! grep -q 'darwin-legacy-option' "$COMMAND_LOG"
	! grep -q '^verify ' "$COMMAND_LOG"
	! grep -q '^brew ' "$COMMAND_LOG"
}
