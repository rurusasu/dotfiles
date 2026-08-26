#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_URL="${DOTFILES_REPOSITORY_URL:-https://github.com/rurusasu/dotfiles.git}"
REPOSITORY_REF="${DOTFILES_REPOSITORY_REF:-refs/heads/main}"
CHECKOUT="${DOTFILES_TART_CHECKOUT:-$HOME/.dotfiles}"
STATE_FILE="${DOTFILES_TART_STATE_FILE:-$HOME/.local/state/dotfiles/tart-applied-commit}"
APPLY_COMMAND="${DOTFILES_TART_APPLY_COMMAND:-}"

die() {
  printf 'tart-sync: %s\n' "$*" >&2
  exit 1
}

remote_hash() {
  local output hash="" ref="" extra candidate_hash candidate_ref count=0
  output="$(git ls-remote --exit-code --refs "$REPOSITORY_URL" "$REPOSITORY_REF")" ||
    die "Unable to resolve $REPOSITORY_REF from $REPOSITORY_URL"

  while read -r candidate_hash candidate_ref extra; do
    [[ -n $candidate_hash && -n $candidate_ref && -z ${extra:-} ]] ||
      die "Remote returned an unexpected revision for $REPOSITORY_REF"
    hash="$candidate_hash"
    ref="$candidate_ref"
    ((count += 1))
  done <<<"$output"
  ((count == 1)) || die "Remote returned an ambiguous revision for $REPOSITORY_REF"
  if [[ $REPOSITORY_REF == refs/* ]]; then
    [[ $ref == "$REPOSITORY_REF" ]] ||
      die "Remote returned an unexpected revision for $REPOSITORY_REF"
  else
    [[ $ref == "refs/heads/$REPOSITORY_REF" || $ref == "refs/tags/$REPOSITORY_REF" ]] ||
      die "Remote returned an unexpected revision for $REPOSITORY_REF"
  fi
  [[ -n $hash ]] ||
    die "Remote returned an unexpected revision for $REPOSITORY_REF"
  [[ $hash =~ ^[0-9a-fA-F]{40}([0-9a-fA-F]{24})?$ ]] ||
    die "Remote returned an invalid commit hash for $REPOSITORY_REF"
  printf '%s\n' "${hash,,}"
}

checkout_hash() {
  [[ -d $CHECKOUT/.git ]] || return 1
  git -C "$CHECKOUT" rev-parse --verify HEAD 2>/dev/null
}

apply_checkout() {
  if [[ -n $APPLY_COMMAND ]]; then
    [[ -x $APPLY_COMMAND ]] || die "Apply command is not executable: $APPLY_COMMAND"
    "$APPLY_COMMAND" "$CHECKOUT"
  else
    "$CHECKOUT/scripts/sh/install-tart-guest.sh" "$CHECKOUT"
  fi
}

main() {
  command -v git >/dev/null 2>&1 || die "git is required"
  local target current recorded=""
  target="$(remote_hash)"
  current="$(checkout_hash || true)"
  [[ -f $STATE_FILE && ! -L $STATE_FILE ]] && recorded="$(<"$STATE_FILE")"

  if [[ $recorded == "$target" && $current == "$target" ]]; then
    printf 'tart-sync: %s is already applied; skipping.\n' "$target"
    return 0
  fi

  if [[ -e $CHECKOUT && ! -d $CHECKOUT/.git ]]; then
    die "Checkout exists but is not a Git repository: $CHECKOUT"
  fi
  if [[ ! -d $CHECKOUT/.git ]]; then
    mkdir -p "$(dirname "$CHECKOUT")"
    git clone --no-checkout --filter=blob:none "$REPOSITORY_URL" "$CHECKOUT"
  fi

  git -C "$CHECKOUT" fetch --force --depth=1 "$REPOSITORY_URL" "$target"
  git -C "$CHECKOUT" checkout --detach --force "$target"
  apply_checkout

  mkdir -p "$(dirname "$STATE_FILE")"
  local temporary_state
  temporary_state="${STATE_FILE}.tmp.$$"
  trap 'rm -f -- "$temporary_state"' EXIT
  printf '%s\n' "$target" >"$temporary_state"
  chmod 600 "$temporary_state"
  mv -f -- "$temporary_state" "$STATE_FILE"
  trap - EXIT
  printf 'tart-sync: applied %s.\n' "$target"
}

main "$@"
