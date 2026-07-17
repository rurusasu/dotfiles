#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	SETS="$REPO_ROOT/nix/packages/sets.nix"
}

@test "catalog defines provider coverage outputs" {
	grep -q 'supportReport' "$SETS"
	grep -q 'providerErrors' "$SETS"
	grep -q 'darwinCasks' "$SETS"
	grep -q 'linuxSystemModules' "$SETS"
}

@test "cross-platform applications are not classified as Windows-only" {
	windows_only="$(sed -n '/windowsOnly = {/,/^  };/p' "$SETS")"
	for package_id in \
		Docker.DockerDesktop \
		dprint.dprint \
		hadolint.hadolint \
		Google.Chrome \
		Microsoft.VisualStudioCode \
		OpenAI.Codex \
		Oven-sh.Bun \
		zig.zig; do
		[[ "$windows_only" != *"\"$package_id\""* ]]
	done
}

@test "Docker declares Darwin cask and Linux system providers" {
	run awk '
		/docker-desktop = \{/ { in_entry=1 }
		in_entry { print }
		in_entry && /^    };/ { exit }
	' "$SETS"
	[ "$status" -eq 0 ]
	[[ "$output" == *'winget = "Docker.DockerDesktop"'* ]]
	[[ "$output" == *'cask = "docker-desktop"'* ]]
	[[ "$output" == *'systemModule = "docker"'* ]]
}

@test "true Windows-only packages carry unsupported reasons" {
	grep -q 'windowsOnlySupport' "$SETS"
	grep -q 'Microsoft.PowerToys' "$SETS"
	grep -q 'Windows system utility' "$SETS"
}

@test "support report derivation and CI gate are wired" {
	grep -q 'package-support-report' "$REPO_ROOT/nix/flakes/packages.nix"
	grep -q 'package-provider-coverage' "$REPO_ROOT/nix/flakes/packages.nix"
	grep -q 'Verify package provider coverage' "$REPO_ROOT/.github/workflows/ci-consistency.yml"
}

@test "missing providers require an explicitly reviewed unsupported reason" {
	grep -q 'reviewedUnsupported' "$SETS"
	grep -q 'missing.*provider or reviewed unsupported reason' "$SETS"
	! grep -q '{ unsupported = "No Windows provider is configured"; }' "$SETS"
}

@test "catalog Winget packages preserve ID-keyed metadata" {
	grep -q 'attachWingetIdMetadata' "$REPO_ROOT/nix/packages/winget.nix"
	grep -q 'attachWingetIdMetadata id' "$REPO_ROOT/nix/packages/winget.nix"
}
