#!/usr/bin/env bats
# Unit tests for _dcnvim_session_name from nix/home/dcnvim-session-name.sh.
# Goal: keep session name in sync with `tm` (Linux): ghq slug basename if
# the workspace lives under ghq root, otherwise basename of the workspace.

setup() {
	HELPER="$BATS_TEST_DIRNAME/../../nix/home/dcnvim-session-name.sh"
	# shellcheck source=/dev/null
	source "$HELPER"
}

@test "ghq 配下なら slug の basename を返す" {
	run _dcnvim_session_name "/home/u/ghq/github.com/rurusasu/dotfiles" "/home/u/ghq"
	[ "$status" -eq 0 ]
	[ "$output" = "dotfiles" ]
}

@test "ghq 配下で末尾スラッシュ付きでも安全" {
	run _dcnvim_session_name "/home/u/ghq/github.com/foo/bar/" "/home/u/ghq"
	[ "$status" -eq 0 ]
	[ "$output" = "bar" ]
}

@test "ghq 配下でないなら workspace の basename" {
	run _dcnvim_session_name "/tmp/myproject" "/home/u/ghq"
	[ "$status" -eq 0 ]
	[ "$output" = "myproject" ]
}

@test "ghq_root 空文字なら basename にフォールバック" {
	run _dcnvim_session_name "/tmp/anything" ""
	[ "$status" -eq 0 ]
	[ "$output" = "anything" ]
}

@test "workspace が単一 segment でも basename を返す" {
	run _dcnvim_session_name "/repo" ""
	[ "$status" -eq 0 ]
	[ "$output" = "repo" ]
}

@test "末尾スラッシュ単独パスでも壊れない" {
	run _dcnvim_session_name "/home/u/ghq/github.com/foo/bar" "/home/u/ghq/"
	[ "$status" -eq 0 ]
	[ "$output" = "bar" ]
}
