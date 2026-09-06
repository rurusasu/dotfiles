#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "WezTerm provides Darwin terminfo before spawning shells" {
	local config="$REPO_ROOT/chezmoi/terminals/wezterm/wezterm.lua"

	run grep -F 'config.set_environment_variables.TERMINFO_DIRS' "$config"
	[ "$status" -eq 0 ]
	run grep -F 'os.getenv("TERMINFO_DIRS")' "$config"
	[ "$status" -eq 0 ]
	run grep -F '/etc/profiles/per-user/' "$config"
	[ "$status" -eq 0 ]
}

@test "WezTerm sends DEL for macOS Backspace while IME remains enabled" {
	local config="$REPO_ROOT/chezmoi/terminals/wezterm/wezterm.lua"
	grep -Fq 'config.use_ime = true' "$config"
	grep -Fq 'if is_macos then' "$config"
	grep -Fq 'action = act.SendString("\x7f")' "$config"
	grep -Fq '{ key = "Backspace", mods = "LEADER"' "$config"
}

@test "Chromium Compose service follows the host platform" {
	run awk '
		/^  chromium:/ { in_chromium=1; next }
		in_chromium && /^  [A-Za-z0-9_-]+:/ { exit }
		in_chromium && /platform:/ { found=1 }
		END { exit(found ? 1 : 0) }
	' "$REPO_ROOT/docker/hermes-service/compose.yml"
	[ "$status" -eq 0 ]
	run grep -F 'ARG TARGETARCH' "$REPO_ROOT/docker/hermes-browser/Dockerfile"
	[ "$status" -eq 0 ]
	run grep -F 'arm64)' "$REPO_ROOT/docker/hermes-browser/Dockerfile"
	[ "$status" -eq 0 ]
}

@test "README documents the one-command macOS installer" {
	run grep -F './install.sh' "$REPO_ROOT/README.md"
	[ "$status" -eq 0 ]
	run grep -F 'Docker Desktop' "$REPO_ROOT/README.md"
	[ "$status" -eq 0 ]
}

@test "devcontainer CI watches macOS installer files" {
	run grep -F '"install.sh"' "$REPO_ROOT/.github/workflows/ci-devcontainer.yml"
	[ "$status" -eq 0 ]
	run grep -F '"scripts/sh/install-macos.sh"' "$REPO_ROOT/.github/workflows/ci-devcontainer.yml"
	[ "$status" -eq 0 ]
}

@test "macOS devcontainer CI allows the cold start and full test suite to finish" {
	run awk '
		/name: E2E \(macOS\)/ { in_job = 1 }
		in_job && /timeout-minutes:/ { exit !($2 >= 60) }
		END { if (!in_job) exit 1 }
	' "$REPO_ROOT/.github/workflows/ci-devcontainer.yml"
	[ "$status" -eq 0 ]
}
