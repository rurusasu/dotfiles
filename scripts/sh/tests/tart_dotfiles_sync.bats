#!/usr/bin/env bats
setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  SYNC_SCRIPT="$REPO_ROOT/scripts/sh/sync-tart-dotfiles.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  REMOTE_REPO="$BATS_TEST_TMPDIR/remote.git"
  SEED_REPO="$BATS_TEST_TMPDIR/seed"
  CHECKOUT="$HOME/checkout with spaces"
  STATE_FILE="$HOME/.local/state/dotfiles/tart-applied-commit"
  REPOSITORY_REF=main
  export APPLY_LOG="$BATS_TEST_TMPDIR/apply.log"
  mkdir -p "$HOME"
  git init --bare "$REMOTE_REPO" >/dev/null
  git init -b main "$SEED_REPO" >/dev/null
  git -C "$SEED_REPO" config user.name test
  git -C "$SEED_REPO" config user.email test@example.com
  printf 'one\n' >"$SEED_REPO/version.txt"
  cat >"$SEED_REPO/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$(cd -- "$(dirname -- "$0")" && pwd)" >>"$APPLY_LOG"
[[ $# == 0 ]]
[[ ${FAIL_APPLY:-0} != 1 ]]
EOF
  chmod +x "$SEED_REPO/install.sh"
  git -C "$SEED_REPO" add version.txt install.sh
  git -C "$SEED_REPO" commit -m initial >/dev/null
  git -C "$SEED_REPO" remote add origin "$REMOTE_REPO"
  git -C "$SEED_REPO" push -u origin main >/dev/null
}
sync_dotfiles() {
  run env DOTFILES_REPOSITORY_URL="$REMOTE_REPO" DOTFILES_REPOSITORY_REF="$REPOSITORY_REF" \
    DOTFILES_TART_CHECKOUT="$CHECKOUT" DOTFILES_TART_STATE_FILE="$STATE_FILE" "$SYNC_SCRIPT"
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
@test "native guest sync applies new revisions once and skips an unchanged revision" {
  sync_dotfiles
  [ "$status" -eq 0 ]
  [ "$(cat "$APPLY_LOG")" = "$CHECKOUT" ]
  [ "$(cat "$STATE_FILE")" = "$(remote_head)" ]
  [ "$(git -C "$CHECKOUT" rev-parse HEAD)" = "$(remote_head)" ]
  : >"$APPLY_LOG"
  sync_dotfiles
  [ "$status" -eq 0 ]
  [[ $output == *"already applied"* ]]
  [ ! -s "$APPLY_LOG" ]
  push_update two
  sync_dotfiles
  [ "$status" -eq 0 ]
  [ "$(cat "$CHECKOUT/version.txt")" = two ]
  [ "$(cat "$APPLY_LOG")" = "$CHECKOUT" ]
  [ "$(cat "$STATE_FILE")" = "$(remote_head)" ]
}
@test "annotated tag records the peeled commit and skips the second apply" {
  git -C "$SEED_REPO" tag -a tart-v1 -m tart-v1
  git -C "$SEED_REPO" push origin refs/tags/tart-v1 >/dev/null
  peeled_commit="$(git -C "$SEED_REPO" rev-parse 'refs/tags/tart-v1^{}')"
  REPOSITORY_REF=refs/tags/tart-v1
  sync_dotfiles
  [ "$status" -eq 0 ]
  [ "$(cat "$STATE_FILE")" = "$peeled_commit" ]
  [ "$(git -C "$CHECKOUT" rev-parse HEAD)" = "$peeled_commit" ]
  : >"$APPLY_LOG"
  sync_dotfiles
  [ "$status" -eq 0 ]
  [[ $output == *"already applied"* ]]
  [ ! -s "$APPLY_LOG" ]
}
@test "existing checkout fetches from an overridden repository URL" {
  sync_dotfiles
  [ "$status" -eq 0 ]
  alt_remote="$BATS_TEST_TMPDIR/fork.git"
  git clone --bare "$REMOTE_REPO" "$alt_remote" >/dev/null
  git -C "$SEED_REPO" remote add fork "$alt_remote"
  printf 'fork-only\n' >"$SEED_REPO/version.txt"
  git -C "$SEED_REPO" add version.txt
  git -C "$SEED_REPO" commit -m fork-only >/dev/null
  git -C "$SEED_REPO" push fork main >/dev/null
  REMOTE_REPO="$alt_remote"
  sync_dotfiles
  [ "$status" -eq 0 ]
  [ "$(cat "$CHECKOUT/version.txt")" = fork-only ]
  [ "$(cat "$STATE_FILE")" = "$(remote_head)" ]
}
@test "failed OS activation preserves the last successfully applied guest revision" {
  sync_dotfiles
  [ "$status" -eq 0 ]
  previous_hash="$(cat "$STATE_FILE")"
  push_update broken
  : >"$APPLY_LOG"
  export FAIL_APPLY=1
  sync_dotfiles
  [ "$status" -ne 0 ]
  [ "$(cat "$APPLY_LOG")" = "$CHECKOUT" ]
  [ "$(cat "$STATE_FILE")" = "$previous_hash" ]
}
@test "Tart launcher establishes one persistent SSH control connection and streams the sync script" {
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
  grep -Eq 'ssh .* -M .* -f -N admin@192\.0\.2\.10' "$launcher_log"
  grep -Eq "ssh .* -S .* admin@192\.0\.2\.10 DOTFILES_RUNTIME=tart DOTFILES_REPOSITORY_URL=https://example.invalid/dotfiles.git DOTFILES_REPOSITORY_REF=feature/review-fix bash -s" "$launcher_log"
  grep -Eq 'ssh -S .* -O exit admin@192\.0\.2\.10' "$launcher_log"
}
