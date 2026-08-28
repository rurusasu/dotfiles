#!/usr/bin/env bash
# shellcheck disable=SC2016 # jq variables must not be expanded by the shell.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
NIX_COMMAND="${DOTFILES_NIX_COMMAND:-nix}"
JQ_COMMAND="${DOTFILES_JQ_COMMAND:-jq}"
BREW_COMMAND="${DOTFILES_BREW_COMMAND:-brew}"
VERIFY_COMMAND="${DOTFILES_DARWIN_VERIFY_COMMAND:-$ROOT/scripts/sh/verify-darwin-package.sh}"

usage() {
  cat <<'EOF'
Usage: migrate-darwin-provider.sh (--id ID | --all) [--feature FEATURE ...]
EOF
}

die() {
  printf 'migrate-darwin-provider: %s\n' "$*" >&2
  exit 1
}

selector=""
selected_id=""
enabled_features=()

while (($# > 0)); do
  case "$1" in
  --id)
    (($# >= 2)) || die "--id requires a value"
    [[ -z $selector ]] || die "--id and --all are mutually exclusive"
    selector="id"
    selected_id="$2"
    shift 2
    ;;
  --all)
    [[ -z $selector ]] || die "--id and --all are mutually exclusive"
    selector="all"
    shift
    ;;
  --feature)
    (($# >= 2)) || die "--feature requires a value"
    enabled_features[${#enabled_features[@]}]="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "unknown argument: $1" ;;
  esac
done

[[ -n $selector ]] || die "exactly one of --id or --all is required"

build_output() {
  local installable="$1" realized
  realized="$("$NIX_COMMAND" build "$installable" --no-link --print-out-paths)"
  [[ -n $realized && $realized != *$'\n'* ]] ||
    die "expected one realized path for $installable"
  printf '%s\n' "$realized"
}

feature_is_enabled() {
  local required_feature="$1" feature
  [[ -z $required_feature ]] && return 0
  ((${#enabled_features[@]} > 0)) || return 1
  for feature in "${enabled_features[@]}"; do
    [[ $feature != "$required_feature" ]] || return 0
  done
  return 1
}

valid_homebrew_token() {
  local token="$1"
  [[ $token =~ ^[A-Za-z0-9][A-Za-z0-9@+._-]*(/[A-Za-z0-9][A-Za-z0-9@+._-]*)*$ ]]
}

legacy_package_is_installed() {
  local provider="$1" name="$2" status
  case "$provider" in
  homebrew-cask)
    if "$BREW_COMMAND" list --cask --versions "$name" >/dev/null; then
      return 0
    else
      status=$?
    fi
    ;;
  homebrew-formula)
    if "$BREW_COMMAND" list --formula --versions "$name" >/dev/null; then
      return 0
    else
      status=$?
    fi
    ;;
  esac
  [[ $status == 1 ]] || die "failed to inspect legacy Homebrew package $name"
  return 1
}

migrate_id() {
  local package_id="$1" legacy_json legacy_provider legacy_name install_feature store_path
  [[ $package_id =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || die "invalid catalog ID: $package_id"

  "$JQ_COMMAND" -e --arg id "$package_id" '.[$id] != null' "$support_json" >/dev/null ||
    die "catalog ID is missing from support report: $package_id"
  legacy_json="$("$JQ_COMMAND" -c --arg id "$package_id" '.[$id].legacyDarwin // null' "$support_json")"
  [[ $legacy_json != "null" ]] || return 0

  legacy_provider="$("$JQ_COMMAND" -r '.provider // ""' <<<"$legacy_json")"
  legacy_name="$("$JQ_COMMAND" -r '.name // ""' <<<"$legacy_json")"
  case "$legacy_provider" in
  homebrew-cask | homebrew-formula) ;;
  *) die "unsupported legacy Darwin provider for $package_id: ${legacy_provider:-missing}" ;;
  esac
  [[ -n $legacy_name ]] || die "legacy Darwin package name is missing for $package_id"
  valid_homebrew_token "$legacy_name" ||
    die "invalid legacy Homebrew token for $package_id: $legacy_name"

  install_feature="$("$JQ_COMMAND" -r --arg id "$package_id" '.[$id].installFeature // ""' "$support_json")"
  feature_is_enabled "$install_feature" || return 0
  legacy_package_is_installed "$legacy_provider" "$legacy_name" || return 0

  store_path="$(build_output ".#darwin-$package_id")"
  "$VERIFY_COMMAND" \
    --support-json "$support_json" \
    --id "$package_id" \
    --store-path "$store_path"

  case "$legacy_provider" in
  homebrew-cask) "$BREW_COMMAND" uninstall --cask "$legacy_name" ;;
  homebrew-formula) "$BREW_COMMAND" uninstall --formula "$legacy_name" ;;
  esac
}

cd "$ROOT"
support_path="$(build_output ".#package-support-report")"
support_json="$support_path/support.json"
darwin_packages_json="$support_path/darwin-packages.json"
[[ -f $support_json ]] || die "support report is unavailable: $support_json"
[[ -f $darwin_packages_json ]] || die "Darwin package list is unavailable: $darwin_packages_json"

if [[ $selector == "id" ]]; then
  migrate_id "$selected_id"
else
  package_ids=()
  while IFS= read -r -d '' package_id; do
    package_ids[${#package_ids[@]}]="$package_id"
  done < <("$JQ_COMMAND" -j '.[] | ., "\u0000"' "$darwin_packages_json")
  if ((${#package_ids[@]} > 0)); then
    for package_id in "${package_ids[@]}"; do
      migrate_id "$package_id"
    done
  fi
fi
