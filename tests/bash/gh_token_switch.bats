#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	HELPER="$REPO_ROOT/chezmoi/dot_config/shell/gh-token-switch.sh"
	TEST_REPO="$BATS_TEST_TMPDIR/repo"
	FAKE_GH="$BATS_TEST_TMPDIR/fake-gh"
	mkdir -p "$TEST_REPO"
	cat >"$FAKE_GH" <<'EOF'
#!/usr/bin/env bash
printf 'token=%s\n' "${GH_TOKEN:-}"
printf 'args=%s\n' "$*"
exit 23
EOF
	chmod +x "$FAKE_GH"
	export DOTFILES_GH_BIN="$FAKE_GH"
}

teardown() {
	unset GH_TOKEN GITHUB_WORK_TOKEN DOTFILES_GH_BIN
}

init_repo() {
	local remote_url="$1"
	git -C "$TEST_REPO" init >/dev/null
	git -C "$TEST_REPO" remote add origin "$remote_url"
}

@test "work remote uses GITHUB_WORK_TOKEN for gh" {
	init_repo "git@github-work:org/repo.git"
	export GH_TOKEN="personal-token"
	export GITHUB_WORK_TOKEN="work-token"
	# shellcheck source=/dev/null
	source "$HELPER"

	cd "$TEST_REPO"
	run gh pr list

	[ "$status" -eq 23 ]
	[[ "$output" == *"token=work-token"* ]]
	[[ "$output" == *"args=pr list"* ]]
	[ "$GH_TOKEN" = "personal-token" ]
}

@test "personal remote keeps existing GH_TOKEN" {
	init_repo "git@github.com:rurusasu/dotfiles.git"
	export GH_TOKEN="personal-token"
	export GITHUB_WORK_TOKEN="work-token"
	# shellcheck source=/dev/null
	source "$HELPER"

	cd "$TEST_REPO"
	run gh issue list

	[ "$status" -eq 23 ]
	[[ "$output" == *"token=personal-token"* ]]
	[ "$GH_TOKEN" = "personal-token" ]
}

@test "outside a repo keeps existing GH_TOKEN" {
	export GH_TOKEN="personal-token"
	export GITHUB_WORK_TOKEN="work-token"
	# shellcheck source=/dev/null
	source "$HELPER"

	cd "$BATS_TEST_TMPDIR"
	run gh auth status

	[ "$status" -eq 23 ]
	[[ "$output" == *"token=personal-token"* ]]
}

@test "work repo without GITHUB_WORK_TOKEN keeps GH_TOKEN" {
	init_repo "git@github-work:org/repo.git"
	export GH_TOKEN="personal-token"
	unset GITHUB_WORK_TOKEN
	# shellcheck source=/dev/null
	source "$HELPER"

	cd "$TEST_REPO"
	run gh repo view

	[ "$status" -eq 23 ]
	[[ "$output" == *"token=personal-token"* ]]
}
