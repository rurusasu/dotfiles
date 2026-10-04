#!/usr/bin/env bash
# Preserve the former chezmoi files before Home Manager installs its links.
# Called twice: read-only before checkLinkTargets, then after writeBoundary.
set -euo pipefail

fail() {
  printf 'Neovim migration: %s\n' "$*" >&2
  exit 1
}

[[ $# == 3 ]] || fail 'expected check|apply, a home-relative config directory, and the Nix store'
mode=$1
relative=$2
store=$3
[[ $mode == check || $mode == apply ]] || fail "unknown mode: $mode"
case "/$relative/" in
  *'/../'* | *'/./'* | *'//'*) fail "unsafe config directory: $relative" ;;
esac
[[ $relative != /* && -n $relative ]] || fail 'config directory must be home-relative'
home=${HOME:?}
home=${home%/}
root="$home/$relative"
store=$(readlink -e -- "$store") || fail 'cannot resolve the Nix store'
suffix=.pre-home-manager

check_parents() {
  local parent="$root/after"
  while [[ $parent != "$home" ]]; do
    [[ ! -L $parent ]] || fail "symlinked parent requires manual migration: $parent"
    [[ ! -e $parent || -d $parent ]] || fail "expected a directory: $parent"
    parent=${parent%/*}
  done
}

managed_link() {
  local path=$1 name=$2 target generation rest
  [[ -e $path ]] || return 1
  target=$(readlink -- "$path") || return 1
  [[ $target == "$store/"* ]] || return 1
  rest=${target#"$store/"}
  generation=${rest%%/*}
  # A whole generation is immutable. Require the exact home-relative target,
  # not merely a substring that could accept another file or path traversal.
  [[ $generation == *-home-manager-files && $rest == "$generation/$relative/$name" ]]
}

pending=()
check_parents
for name in init.lua lua after/lsp; do
  path="$root/$name"
  if [[ -L $path ]]; then
    managed_link "$path" "$name" || fail "foreign or dangling symlink requires manual migration: $path"
    # A moved store symlink is not a durable backup: garbage collection could
    # delete its contents. Only real legacy directories are retired here.
    [[ $name != after/lsp ]] || fail "after/lsp symlink requires a manual durable backup: $path"
  elif [[ ! -e $path ]]; then
    continue
  fi
  if [[ $name == init.lua ]]; then
    [[ -f $path ]] || fail "expected a regular file: $path"
  else
    [[ -d $path ]] || fail "expected a directory: $path"
  fi
  # init.lua/lua already managed by HM need no backup or relinking here.
  [[ -L $path ]] && continue
  backup="$path$suffix"
  [[ ! -e $backup && ! -L $backup ]] || fail "backup already exists; preserve it and migrate manually: $backup"
  pending+=("$path")
done

# Every candidate has been checked before the first mutation. An apply call
# performs the same preflight again rather than trusting an earlier check.
[[ $mode == apply ]] || exit 0
for path in "${pending[@]}"; do
  backup="$path$suffix"
  if [[ -v DRY_RUN ]]; then
    printf 'Would preserve %s as %s\n' "$path" "$backup"
    continue
  fi
  check_parents
  [[ ! -e $backup && ! -L $backup ]] || fail "backup appeared during migration: $backup"
  # GNU coreutils is supplied by the Nix wrapper on both Linux and Darwin.
  # -T prevents moving INTO a directory that races with the preflight; -n
  # preserves a raced destination. Since -n may return success without moving,
  # the source must also have disappeared before linkGeneration can proceed.
  mv --no-clobber --no-target-directory -- "$path" "$backup" || fail "could not preserve: $path"
  [[ ! -e $path && ! -L $path ]] || fail "source remains after backup; refusing to link: $path"
  printf 'Preserved %s as %s\n' "$path" "$backup"
done
