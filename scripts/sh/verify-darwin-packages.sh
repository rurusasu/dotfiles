#!/usr/bin/env bash
# shellcheck disable=SC2016 # jq variables must not be expanded by the shell.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
NIX_COMMAND="${DOTFILES_NIX_COMMAND:-nix}"
JQ_COMMAND="${DOTFILES_JQ_COMMAND:-jq}"
VERIFY_COMMAND="${DOTFILES_DARWIN_VERIFY_COMMAND:-$ROOT/scripts/sh/verify-darwin-package.sh}"

die() {
  printf 'verify-darwin-packages: %s\n' "$*" >&2
  exit 1
}

features_json='[]'
while (($# > 0)); do
  case "$1" in
  --feature)
    (($# >= 2)) || die "--feature requires a value"
    features_json="$("$JQ_COMMAND" -c --arg feature "$2" '. + [$feature]' <<<"$features_json")"
    shift 2
    ;;
  -h | --help)
    printf 'Usage: verify-darwin-packages.sh [--feature FEATURE ...]\n'
    exit 0
    ;;
  *) die "unknown argument: $1" ;;
  esac
done

cd "$ROOT"
# One report evaluation records metadata and exact output paths. The report
# does not realize optional applications; active outputs must already exist
# after nix-darwin activation.
report_path="$("$NIX_COMMAND" build .#package-support-report --no-link --print-out-paths)"
[[ -n $report_path && $report_path != *$'\n'* ]] || die "expected one support report path"
support_json="$report_path/support.json"
paths_json="$report_path/darwin-paths.json"
[[ -f $support_json && -f $paths_json ]] || die "Darwin verification report is unavailable: $report_path"

package_ids="$("$JQ_COMMAND" -r --argjson features "$features_json" '
  to_entries[]
  | select(.value.darwin.provider == "nix")
  | select((.value.darwin.identity | type) == "object")
  | select(.value.installFeature == null or (.value.installFeature as $feature | $features | index($feature) != null))
  | .key
' "$support_json")"
[[ -n $package_ids ]] || exit 0

while IFS= read -r package_id; do
  [[ $package_id =~ ^[A-Za-z_][A-Za-z0-9._+-]*$ ]] || die "invalid catalog ID: $package_id"
done <<<"$package_ids"

while IFS= read -r package_id; do
  store_path="$("$JQ_COMMAND" -er --arg id "$package_id" '.[$id] | select(type == "string" and length > 0)' "$paths_json")"
  "$VERIFY_COMMAND" --support-json "$support_json" --id "$package_id" --store-path "$store_path"
done <<<"$package_ids"
