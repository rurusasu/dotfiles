#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}
@test "Claude and TablePlus are not managed by dotfiles" {
	[ -z "$(find "$REPO_ROOT/chezmoi/dot_claude" -type f -print 2>/dev/null)" ]
	[ -z "$(find "$REPO_ROOT/chezmoi/AppData/Roaming/Claude" -type f -print 2>/dev/null)" ]
	[ ! -e "$REPO_ROOT/scripts/powershell/handlers/Handler.ClaudeCode.ps1" ]
	[ -e "$REPO_ROOT/chezmoi/dot_agents/skills/create-agentsmd/SKILL.md" ]
}
@test "DeepSeek Harness remains in chezmoi global pnpm data" {
	grep -q '"@deepseek-ai/dsh"' "$REPO_ROOT/chezmoi/.chezmoidata/pnpm_global.yaml"
}
@test "DeepSeek Harness native builds are pre-approved for pnpm global installs" {
	command -v chezmoi >/dev/null 2>&1 || skip "chezmoi is required to render the Linux/macOS installer"

	for os in linux darwin; do
		test_dir="$BATS_TEST_TMPDIR/deepseek-$os"
		mkdir -p "$test_dir/bin" "$test_dir/home"
		cat > "$test_dir/bin/pnpm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "list" ] && [ "${2:-}" = "-g" ]; then
	printf '[]\n'
	exit 0
fi

{
	printf 'CALL'
	printf '\t%s' "$@"
	printf '\n'
} >> "$PNPM_CALL_LOG"
EOF
		chmod +x "$test_dir/bin/pnpm"

		rendered="$test_dir/install-pnpm-global.sh"
		chezmoi --config /dev/null --config-format toml --source "$REPO_ROOT/chezmoi" \
			--destination "$test_dir/home" \
			--cache "$test_dir/cache" \
			--persistent-state "$test_dir/state.boltdb" \
			--override-data "{\"chezmoi\":{\"os\":\"$os\"}}" \
			execute-template --file "$REPO_ROOT/chezmoi/.chezmoiscripts/run_onchange_install-pnpm-global.sh.tmpl" \
			> "$rendered"

		run env HOME="$test_dir/home" \
			CHEZMOI_SOURCE_DIR="$REPO_ROOT/chezmoi" \
			PNPM_CALL_LOG="$test_dir/pnpm-calls.log" \
			PATH="$test_dir/bin:$PATH" \
			bash "$rendered"
		[ "$status" -eq 0 ]

		expected_call=$'CALL\tadd\t-g\t--allow-build=@deepseek-ai/dsh-subprocess-local\t--allow-build=@google/genai\t--allow-build=koffi\t--allow-build=node-pty\t--allow-build=protobufjs\t@deepseek-ai/dsh'
		grep -Fqx "$expected_call" "$test_dir/pnpm-calls.log"
	done
}
@test "DeepSeek Harness is reinstalled when the native build approval changes" {
	command -v chezmoi >/dev/null 2>&1 || skip "chezmoi is required to render the Linux/macOS installer"

	test_dir="$BATS_TEST_TMPDIR/deepseek-reinstall"
	mkdir -p "$test_dir/bin" "$test_dir/home"
	cat > "$test_dir/bin/pnpm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "list" ] && [ "${2:-}" = "-g" ]; then
	cat <<'JSON'
[{"dependencies":{"@deepseek-ai/dsh":{"version":"0.1.1-rc.2"}}}]
JSON
	exit 0
fi

{
	printf 'CALL'
	printf '\t%s' "$@"
	printf '\n'
} >> "$PNPM_CALL_LOG"
EOF
	chmod +x "$test_dir/bin/pnpm"

	rendered="$test_dir/install-pnpm-global.sh"
	chezmoi --config /dev/null --config-format toml --source "$REPO_ROOT/chezmoi" \
		--destination "$test_dir/home" \
		--cache "$test_dir/cache" \
		--persistent-state "$test_dir/state.boltdb" \
		--override-data '{"chezmoi":{"os":"linux"}}' \
		execute-template --file "$REPO_ROOT/chezmoi/.chezmoiscripts/run_onchange_install-pnpm-global.sh.tmpl" \
		> "$rendered"

	run env HOME="$test_dir/home" \
		CHEZMOI_SOURCE_DIR="$REPO_ROOT/chezmoi" \
		PNPM_CALL_LOG="$test_dir/pnpm-calls.log" \
		PATH="$test_dir/bin:$PATH" \
		bash "$rendered"
	[ "$status" -eq 0 ]

	remove_call=$'CALL\tremove\t-g\t@deepseek-ai/dsh'
	add_call=$'CALL\tadd\t-g\t--allow-build=@deepseek-ai/dsh-subprocess-local\t--allow-build=@google/genai\t--allow-build=koffi\t--allow-build=node-pty\t--allow-build=protobufjs\t@deepseek-ai/dsh'
	remove_line="$(grep -Fnx "$remove_call" "$test_dir/pnpm-calls.log" | cut -d: -f1)"
	add_line="$(grep -Fnx "$add_call" "$test_dir/pnpm-calls.log" | cut -d: -f1)"
	[ -n "$remove_line" ]
	[ -n "$add_line" ]
	[ "$remove_line" -lt "$add_line" ]
}
@test "pnpm v11 global installs skip packages present in the global manifest" {
	test_dir="$(mktemp -d)"
	mkdir -p "$test_dir/bin"

	cat > "$test_dir/bin/pnpm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "list" ] && [ "${2:-}" = "-g" ]; then
	cat <<'JSON'
[{"dependencies":{
  "@prisma/language-server":{"version":"31.11.0"},
  "@agentclientprotocol/claude-agent-acp":{"version":"0.70.0"},
  "@deepseek-ai/dsh":{"version":"0.1.1-rc.2"},
  "@playwright/cli":{"version":"0.1.18"},
  "typescript-language-server":{"version":"6.0.0"},
  "typescript":{"version":"7.0.2"}
}}]
JSON
	exit 0
fi

exit 1
EOF
	chmod +x "$test_dir/bin/pnpm"

	for package_name in \
		"@prisma/language-server" \
		"@agentclientprotocol/claude-agent-acp" \
		"@deepseek-ai/dsh" \
		"@playwright/cli" \
		typescript-language-server \
		typescript; do
		run env PATH="$test_dir/bin:$PATH" \
			bash -c 'source "$1" && pnpm_global_package_installed "$2"' \
			bash "$REPO_ROOT/chezmoi/.chezmoitemplates/pnpm_global_installed.sh" "$package_name"
		[ "$status" -eq 0 ]
	done

	run env PATH="$test_dir/bin:$PATH" \
		bash -c 'source "$1" && pnpm_global_package_installed "$2"' \
		bash "$REPO_ROOT/chezmoi/.chezmoitemplates/pnpm_global_installed.sh" missing-package
	[ "$status" -ne 0 ]

	rm -rf "$test_dir"
}
@test "CI consistency workflow gates on package provider coverage" {
	grep -q 'Verify package provider coverage' "$REPO_ROOT/.github/workflows/ci-consistency.yml"
}
@test "winget export matches committed Windows manifest data" {
	winget_normalize='.Sources |= sort_by(.SourceDetails.Name) | .Sources |= map(.Packages |= sort_by(.PackageIdentifier))'

	# Ordering and object-key layout are not part of the Winget data contract;
	# package identifiers and all package metadata remain strict. Keep this
	# normalization aligned with ci-consistency.yml.
	generated_fixture='{"Sources":[{"Packages":[{"PackageIdentifier":"z.pkg","Version":"1"},{"PackageIdentifier":"a.pkg","Version":"2"}],"SourceDetails":{"Name":"winget"}},{"Packages":[{"PackageIdentifier":"store.pkg"}],"SourceDetails":{"Name":"msstore"}}]}'
	committed_fixture='{"Sources":[{"SourceDetails":{"Name":"msstore"},"Packages":[{"PackageIdentifier":"store.pkg"}]},{"SourceDetails":{"Name":"winget"},"Packages":[{"Version":"1","PackageIdentifier":"z.pkg"},{"Version":"2","PackageIdentifier":"a.pkg"}]}]}'
	jq -S "$winget_normalize" <<<"$generated_fixture" >"$BATS_TEST_TMPDIR/generated-fixture.json"
	jq -S "$winget_normalize" <<<"$committed_fixture" >"$BATS_TEST_TMPDIR/committed-fixture.json"
	cmp "$BATS_TEST_TMPDIR/generated-fixture.json" "$BATS_TEST_TMPDIR/committed-fixture.json"

	changed_fixture='{"Sources":[{"Packages":[{"PackageIdentifier":"z.pkg","Version":"9"},{"PackageIdentifier":"a.pkg","Version":"2"}],"SourceDetails":{"Name":"winget"}},{"Packages":[{"PackageIdentifier":"store.pkg"}],"SourceDetails":{"Name":"msstore"}}]}'
	jq -S "$winget_normalize" <<<"$changed_fixture" >"$BATS_TEST_TMPDIR/changed-fixture.json"
	if cmp -s "$BATS_TEST_TMPDIR/generated-fixture.json" "$BATS_TEST_TMPDIR/changed-fixture.json"; then
		echo "Package metadata drift was hidden by Winget manifest normalization" >&2
		return 1
	fi

	run --separate-stderr nix build "path:$REPO_ROOT#winget-export" --no-link --print-out-paths
	[ "$status" -eq 0 ]
	[ -d "$output" ]

	if ! diff -u \
		<(jq -S "$winget_normalize" "$output/winget/packages.json") \
		<(jq -S "$winget_normalize" "$REPO_ROOT/windows/winget/packages.json"); then
		echo "Generated Winget manifest data differs from the committed manifest" >&2
		return 1
	fi

	for manifest in npm pnpm; do
		if ! jq --exit-status --slurp '.[0] == .[1]' \
			"$output/$manifest/packages.json" \
			"$REPO_ROOT/windows/$manifest/packages.json"; then
			echo "Generated $manifest manifest data differs from the committed manifest" >&2
			return 1
		fi
	done
}
@test "Darwin Raycast artifact has the declared identity and trusted signature" {
	command -v nix >/dev/null 2>&1 || skip "nix is not available in this test environment"
	command -v codesign >/dev/null 2>&1 || skip "codesign is not available in this test environment"
	command -v plutil >/dev/null 2>&1 || skip "plutil is not available in this test environment"
	command -v spctl >/dev/null 2>&1 || skip "spctl is not available in this test environment"

	run --separate-stderr nix build --no-link --print-out-paths .#darwin-raycast
	[ "$status" -eq 0 ]
	store_path="$output"
	app="$store_path/Applications/Raycast.app"

	run plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist"
	[ "$status" -eq 0 ]
	[ "$output" = "com.raycast.macos" ]
	run plutil -extract CFBundleExecutable raw "$app/Contents/Info.plist"
	[ "$status" -eq 0 ]
	[ "$output" = "Raycast" ]
	run codesign --verify --deep --strict "$app"
	[ "$status" -eq 0 ]
	run spctl --assess --type execute "$app"
	[ "$status" -eq 0 ]
}
@test "Darwin Discord keeps staged modules outside its signed application bundle" {
	command -v nix >/dev/null 2>&1 || skip "nix is not available in this test environment"
	command -v codesign >/dev/null 2>&1 || skip "codesign is not available in this test environment"
	command -v plutil >/dev/null 2>&1 || skip "plutil is not available in this test environment"
	command -v spctl >/dev/null 2>&1 || skip "spctl is not available in this test environment"

	run --separate-stderr nix build --no-link --print-out-paths .#darwin-discord
	[ "$status" -eq 0 ]
	store_path="$output"
	app="$store_path/Applications/Discord.app"

	[ ! -e "$app/Contents/Resources/modules" ]
	[ -d "$store_path/share/discord/modules" ]
	grep -Fq "$store_path/share/discord/modules" "$store_path/bin/Discord"
	run plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist"
	[ "$status" -eq 0 ]
	[ "$output" = "com.hnc.Discord" ]
	run plutil -extract CFBundleExecutable raw "$app/Contents/Info.plist"
	[ "$status" -eq 0 ]
	[ "$output" = "Discord" ]
	run codesign --verify --deep --strict "$app"
	[ "$status" -eq 0 ]
	run spctl --assess --type execute "$app"
	[ "$status" -eq 0 ]
}
