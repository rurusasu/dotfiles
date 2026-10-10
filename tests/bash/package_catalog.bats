#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}
@test "winget export matches committed Windows manifest data" {
	winget_normalize='.Sources |= sort_by(.SourceDetails.Name) | .Sources |= map(.Packages |= sort_by(.PackageIdentifier))'

	# Ordering and object-key layout are not part of the Winget data contract;
	# package identifiers and all package metadata remain strict. Keep this
	# normalization aligned with ci-nix.yml.
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
