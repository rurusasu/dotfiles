#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	SYNC_SCRIPT="$REPO_ROOT/scripts/sh/sync-tart-dotfiles.sh"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	REMOTE_REPO="$BATS_TEST_TMPDIR/remote.git"
	SEED_REPO="$BATS_TEST_TMPDIR/seed"
	CHECKOUT="$TEST_HOME/.dotfiles"
	STATE_FILE="$TEST_HOME/.local/state/dotfiles/tart-applied-commit"
	APPLY_LOG="$BATS_TEST_TMPDIR/apply.log"
	APPLY_SCRIPT="$BATS_TEST_TMPDIR/apply.sh"
	mkdir -p "$TEST_HOME"
	git init --bare "$REMOTE_REPO" >/dev/null
	git init -b main "$SEED_REPO" >/dev/null
	git -C "$SEED_REPO" config user.name test
	git -C "$SEED_REPO" config user.email test@example.com
	printf 'one\n' >"$SEED_REPO/version.txt"
	git -C "$SEED_REPO" add version.txt
	git -C "$SEED_REPO" commit -m initial >/dev/null
	git -C "$SEED_REPO" remote add origin "$REMOTE_REPO"
	git -C "$SEED_REPO" push -u origin main >/dev/null

	cat >"$APPLY_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >>"$APPLY_LOG"
[[ ${FAIL_APPLY:-0} != 1 ]]
EOF
	chmod +x "$APPLY_SCRIPT"
	export HOME APPLY_LOG
}

sync_dotfiles() {
	run env \
		DOTFILES_REPOSITORY_URL="$REMOTE_REPO" \
		DOTFILES_REPOSITORY_REF=refs/heads/main \
		DOTFILES_TART_CHECKOUT="$CHECKOUT" \
		DOTFILES_TART_STATE_FILE="$STATE_FILE" \
		DOTFILES_TART_APPLY_COMMAND="$APPLY_SCRIPT" \
		"$SYNC_SCRIPT"
}

remote_head() {
	git --git-dir "$REMOTE_REPO" rev-parse refs/heads/main
}

push_update() {
	printf '%s\n' "$1" >"$SEED_REPO/version.txt"
	git -C "$SEED_REPO" add version.txt
	git -C "$SEED_REPO" commit -m "$1" >/dev/null
	git -C "$SEED_REPO" push origin main >/dev/null
}

@test "initial sync clones the requested revision applies it and records its hash" {
	sync_dotfiles

	[ "$status" -eq 0 ]
	[ "$(cat "$STATE_FILE")" = "$(remote_head)" ]
	[ "$(git -C "$CHECKOUT" rev-parse HEAD)" = "$(remote_head)" ]
	grep -Fxq "$CHECKOUT" "$APPLY_LOG"
}

@test "shorthand branch ref resolves to its canonical remote ref" {
	run env \
		DOTFILES_REPOSITORY_URL="$REMOTE_REPO" \
		DOTFILES_REPOSITORY_REF=main \
		DOTFILES_TART_CHECKOUT="$CHECKOUT" \
		DOTFILES_TART_STATE_FILE="$STATE_FILE" \
		DOTFILES_TART_APPLY_COMMAND="$APPLY_SCRIPT" \
		"$SYNC_SCRIPT"

	[ "$status" -eq 0 ]
	[ "$(cat "$STATE_FILE")" = "$(remote_head)" ]
}

@test "annotated tag records the peeled commit and skips the second apply" {
	git -C "$SEED_REPO" tag -a tart-v1 -m tart-v1
	git -C "$SEED_REPO" push origin refs/tags/tart-v1 >/dev/null
	peeled_commit="$(git -C "$SEED_REPO" rev-parse 'refs/tags/tart-v1^{}')"

	run env \
		DOTFILES_REPOSITORY_URL="$REMOTE_REPO" \
		DOTFILES_REPOSITORY_REF=refs/tags/tart-v1 \
		DOTFILES_TART_CHECKOUT="$CHECKOUT" \
		DOTFILES_TART_STATE_FILE="$STATE_FILE" \
		DOTFILES_TART_APPLY_COMMAND="$APPLY_SCRIPT" \
		"$SYNC_SCRIPT"

	[ "$status" -eq 0 ]
	[ "$(cat "$STATE_FILE")" = "$peeled_commit" ]
	[ "$(git -C "$CHECKOUT" rev-parse HEAD)" = "$peeled_commit" ]
	: >"$APPLY_LOG"

	run env \
		DOTFILES_REPOSITORY_URL="$REMOTE_REPO" \
		DOTFILES_REPOSITORY_REF=refs/tags/tart-v1 \
		DOTFILES_TART_CHECKOUT="$CHECKOUT" \
		DOTFILES_TART_STATE_FILE="$STATE_FILE" \
		DOTFILES_TART_APPLY_COMMAND="$APPLY_SCRIPT" \
		"$SYNC_SCRIPT"

	[ "$status" -eq 0 ]
	[[ "$output" == *"already applied"* ]]
	[ ! -s "$APPLY_LOG" ]
}

@test "unchanged remote hash skips checkout and apply" {
	sync_dotfiles
	: >"$APPLY_LOG"

	sync_dotfiles

	[ "$status" -eq 0 ]
	[[ "$output" == *"already applied"* ]]
	[ ! -s "$APPLY_LOG" ]
}

@test "changed remote hash fetches and reapplies the checkout" {
	sync_dotfiles
	push_update two
	: >"$APPLY_LOG"

	sync_dotfiles

	[ "$status" -eq 0 ]
	[ "$(cat "$CHECKOUT/version.txt")" = two ]
	[ "$(cat "$STATE_FILE")" = "$(remote_head)" ]
	grep -Fxq "$CHECKOUT" "$APPLY_LOG"
}

@test "existing checkout fetches from an overridden repository URL" {
	alt_remote="$BATS_TEST_TMPDIR/fork.git"
	sync_dotfiles
	git clone --bare "$REMOTE_REPO" "$alt_remote" >/dev/null
	git -C "$SEED_REPO" remote add fork "$alt_remote"
	printf 'fork-only\n' >"$SEED_REPO/version.txt"
	git -C "$SEED_REPO" add version.txt
	git -C "$SEED_REPO" commit -m fork-only >/dev/null
	git -C "$SEED_REPO" push fork main >/dev/null

	run env \
		DOTFILES_REPOSITORY_URL="$alt_remote" \
		DOTFILES_REPOSITORY_REF=main \
		DOTFILES_TART_CHECKOUT="$CHECKOUT" \
		DOTFILES_TART_STATE_FILE="$STATE_FILE" \
		DOTFILES_TART_APPLY_COMMAND="$APPLY_SCRIPT" \
		"$SYNC_SCRIPT"

	[ "$status" -eq 0 ]
	[ "$(cat "$CHECKOUT/version.txt")" = fork-only ]
	[ "$(cat "$STATE_FILE")" = "$(git --git-dir "$alt_remote" rev-parse refs/heads/main)" ]
}

@test "failed apply never advances the applied hash" {
	sync_dotfiles
	previous_hash="$(cat "$STATE_FILE")"
	push_update broken

	run env \
		FAIL_APPLY=1 \
		DOTFILES_REPOSITORY_URL="$REMOTE_REPO" \
		DOTFILES_REPOSITORY_REF=refs/heads/main \
		DOTFILES_TART_CHECKOUT="$CHECKOUT" \
		DOTFILES_TART_STATE_FILE="$STATE_FILE" \
		DOTFILES_TART_APPLY_COMMAND="$APPLY_SCRIPT" \
		"$SYNC_SCRIPT"

	[ "$status" -ne 0 ]
	[ "$(cat "$STATE_FILE")" = "$previous_hash" ]
}

@test "Tart package output contains only the requested CLI set" {
	packages="$REPO_ROOT/nix/flakes/packages.nix"
	sets="$REPO_ROOT/nix/packages/sets.nix"

	grep -q 'tartMinimal = resolve' "$sets"
	for package in git chezmoi neovim codex; do
		grep -q "\"$package\"" "$sets"
	done
	grep -q 'tart-minimal = pkgs.buildEnv' "$packages"
	grep -q 'paths = sets.tartMinimal' "$packages"
}

@test "Tart run task attempts Hindsight non-fatally and uses the managed launcher" {
	taskfile="$REPO_ROOT/taskfiles/install/taskfile.yml"

	run awk '
		/^  tart:run:/ { in_task=1 }
		in_task { print }
		in_task && /^[^ ]/ { exit }
	' "$taskfile"

	[ "$status" -eq 0 ]
	[[ "$output" == *'if ! task hindsight:up'* ]]
	[[ "$output" == *'continuing without shared Hindsight'* ]]
	[[ "$output" == *'scripts/sh/run-tart-vm.sh'* ]]
}

@test "Tart launcher keeps a reverse Hindsight tunnel and runs guest sync" {
	launcher="$REPO_ROOT/scripts/sh/run-tart-vm.sh"

	grep -q -- '-R.*8888.*127.0.0.1' "$launcher"
	grep -q 'sync-tart-dotfiles.sh' "$launcher"
	grep -q 'DOTFILES_RUNTIME=%q' "$launcher"
	grep -q 'DOTFILES_REPOSITORY_URL=%q' "$launcher"
}

@test "Tart launcher establishes one persistent tunnel and streams the sync script" {
	launcher="$REPO_ROOT/scripts/sh/run-tart-vm.sh"
	bin="$BATS_TEST_TMPDIR/launcher-bin"
	launcher_log="$BATS_TEST_TMPDIR/launcher.log"
	started="$BATS_TEST_TMPDIR/tart-started"
	mkdir -p "$bin"
	cat >"$bin/tart" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'tart %s\n' "$*" >>"$LAUNCHER_LOG"
case "${1:-}" in
  run) touch "$TART_STARTED"; sleep 1 ;;
  ip) [[ -e $TART_STARTED ]] && printf '192.0.2.10\n' ;;
esac
EOF
	cat >"$bin/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ssh %s\n' "$*" >>"$LAUNCHER_LOG"
if [[ " $* " == *" true " ]]; then
  attempts=0
  [[ ! -e $SSH_ATTEMPTS ]] || attempts="$(cat "$SSH_ATTEMPTS")"
  attempts=$((attempts + 1))
  printf '%s\n' "$attempts" >"$SSH_ATTEMPTS"
  ((attempts >= 3))
  exit
fi
if [[ " $* " == *" bash -s "* ]]; then
  payload="$(cat)"
  [[ $payload == *'git ls-remote'* ]]
  [[ " $* " == *'DOTFILES_REPOSITORY_URL=https://example.invalid/dotfiles.git'* ]]
  [[ " $* " == *'DOTFILES_REPOSITORY_REF=feature/review-fix'* ]]
fi
EOF
	chmod +x "$bin/tart" "$bin/ssh"

	run env \
		LAUNCHER_LOG="$launcher_log" \
		TART_STARTED="$started" \
		SSH_ATTEMPTS="$BATS_TEST_TMPDIR/ssh-attempts" \
		DOTFILES_REPOSITORY_URL=https://example.invalid/dotfiles.git \
		DOTFILES_REPOSITORY_REF=feature/review-fix \
		DOTFILES_TART_COMMAND="$bin/tart" \
		DOTFILES_TART_SSH_COMMAND="$bin/ssh" \
		DOTFILES_TART_IP_WAIT_DELAY_SECONDS=0 \
		DOTFILES_TART_SSH_WAIT_DELAY_SECONDS=0 \
		DOTFILES_TART_RUN_STATE_DIR="$BATS_TEST_TMPDIR/state" \
		"$launcher"

	[ "$status" -eq 0 ]
	[ "$(cat "$BATS_TEST_TMPDIR/ssh-attempts")" -eq 3 ]
	grep -Eq 'ssh .* -M .* -f -N -R 127\.0\.0\.1:8888:127\.0\.0\.1:8888 admin@192\.0\.2\.10' "$launcher_log"
	grep -Eq "ssh .* -S .* admin@192\.0\.2\.10 DOTFILES_RUNTIME=tart DOTFILES_REPOSITORY_URL=https://example.invalid/dotfiles.git DOTFILES_REPOSITORY_REF=feature/review-fix bash -s" "$launcher_log"
	grep -Eq 'ssh -S .* -O exit admin@192\.0\.2\.10' "$launcher_log"
}

@test "guest installer exposes only the minimal Nix profile and WezTerm cask" {
	installer="$REPO_ROOT/scripts/sh/install-tart-guest.sh"
	bin="$BATS_TEST_TMPDIR/guest-bin"
	store="$BATS_TEST_TMPDIR/store-profile"
	second_store="$BATS_TEST_TMPDIR/store-profile-2"
	guest_log="$BATS_TEST_TMPDIR/guest.log"
	guest_repo="$BATS_TEST_TMPDIR/guest-repo"
	mkdir -p "$bin" "$store/bin" "$second_store/bin" "$guest_repo/chezmoi"
	for command in git chezmoi nvim codex; do
		cat >"$store/bin/$command" <<EOF
#!/usr/bin/env bash
printf '$command %s\n' "\$*" >>"\$GUEST_LOG"
EOF
		chmod +x "$store/bin/$command"
		cp "$store/bin/$command" "$second_store/bin/$command"
	done
	cat >"$bin/nix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'nix_config=%s args=%s\n' "${NIX_CONFIG:-}" "$*" >>"$GUEST_LOG"
[[ ${1:-} == build ]]
while (($#)); do
  if [[ $1 == --out-link ]]; then
    shift
    ln -s "$GUEST_STORE" "$1"
    exit 0
  fi
  shift
done
exit 2
EOF
	cat >"$bin/brew" <<'EOF'
#!/usr/bin/env bash
printf 'brew %s\n' "$*" >>"$GUEST_LOG"
[[ ${1:-} == install ]]
EOF
	chmod +x "$bin/nix" "$bin/brew"

	run env \
		HOME="$BATS_TEST_TMPDIR/guest-home" \
		PATH="$bin:$PATH" \
		GUEST_LOG="$guest_log" \
		GUEST_STORE="$second_store" \
		"$installer" "$guest_repo"

	[ "$status" -eq 0 ]
	[ "$(readlink "$BATS_TEST_TMPDIR/guest-home/.local/state/dotfiles/tart-profile")" = "$second_store" ]
	[ -z "$(find "$store" -maxdepth 1 -name 'tart-profile.next.*' -print -quit)" ]
	run env \
		HOME="$BATS_TEST_TMPDIR/guest-home" \
		PATH="$bin:$PATH" \
		GUEST_LOG="$guest_log" \
		GUEST_STORE="$store" \
		"$installer" "$guest_repo"

	[ "$status" -eq 0 ]
	grep -Fq "nix_config=extra-experimental-features = nix-command flakes args=build $guest_repo#tart-minimal --out-link" "$guest_log"
	grep -Fxq 'brew install --cask wezterm@nightly' "$guest_log"
	grep -Fxq "chezmoi init --source $guest_repo/chezmoi" "$guest_log"
	grep -Fxq 'chezmoi apply --force' "$guest_log"
	[ "$(find "$BATS_TEST_TMPDIR/guest-home/.local/bin" -type l | wc -l | tr -d ' ')" -eq 4 ]
}
