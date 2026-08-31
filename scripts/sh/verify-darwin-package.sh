#!/usr/bin/env bash
# shellcheck disable=SC2016 # jq variables must not be expanded by the shell.
set -euo pipefail

JQ_COMMAND="${DOTFILES_JQ_COMMAND:-jq}"
PLISTBUDDY_COMMAND="${DOTFILES_PLISTBUDDY_COMMAND:-/usr/libexec/PlistBuddy}"
CODESIGN_COMMAND="${DOTFILES_CODESIGN_COMMAND:-/usr/bin/codesign}"
SPCTL_COMMAND="${DOTFILES_SPCTL_COMMAND:-/usr/sbin/spctl}"
OPEN_COMMAND="${DOTFILES_OPEN_COMMAND:-/usr/bin/open}"

usage() {
  cat <<'EOF'
Usage: verify-darwin-package.sh --support-json FILE --id ID --store-path PATH [--launch]
EOF
}

die() {
  printf 'verify-darwin-package: %s\n' "$*" >&2
  exit 1
}

require_path_component() {
  local field_name="$1" value="$2"
  [[ -n $value && $value != "." && $value != ".." && $value != */* ]] ||
    die "$field_name must be a single path component"
}

support_json=""
package_id=""
store_path=""
launch=0

while (($# > 0)); do
  case "$1" in
  --support-json)
    (($# >= 2)) || die "--support-json requires a value"
    support_json="$2"
    shift 2
    ;;
  --id)
    (($# >= 2)) || die "--id requires a value"
    package_id="$2"
    shift 2
    ;;
  --store-path)
    (($# >= 2)) || die "--store-path requires a value"
    store_path="$2"
    shift 2
    ;;
  --launch)
    launch=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "unknown argument: $1" ;;
  esac
done

[[ -n $support_json ]] || die "--support-json is required"
[[ -n $package_id ]] || die "--id is required"
[[ -n $store_path ]] || die "--store-path is required"
[[ -f $support_json ]] || die "support report is unavailable: $support_json"
[[ -d $store_path ]] || die "realized store path is unavailable: $store_path"

"$JQ_COMMAND" -e --arg id "$package_id" '.[$id] != null' "$support_json" >/dev/null ||
  die "catalog ID is missing from support report: $package_id"

provider="$("$JQ_COMMAND" -r --arg id "$package_id" '.[$id].darwin.provider // ""' "$support_json")"
[[ $provider == "nix" ]] || die "Darwin provider for $package_id is not nix: ${provider:-missing}"

verification_kind="$("$JQ_COMMAND" -r --arg id "$package_id" '
  if (.[$id].darwin.identity? | type) != "object" then ""
  elif (.[$id].darwin.identity.appName? // "") != "" then "app"
  elif (.[$id].darwin.identity.command? // "") != "" then "command"
  else ""
  end
' "$support_json")"

case "$verification_kind" in
app)
  app_name="$("$JQ_COMMAND" -r --arg id "$package_id" '.[$id].darwin.identity.appName // ""' "$support_json")"
  expected_bundle_id="$("$JQ_COMMAND" -r --arg id "$package_id" '.[$id].darwin.identity.bundleId // ""' "$support_json")"
  expected_executable="$("$JQ_COMMAND" -r --arg id "$package_id" '.[$id].darwin.identity.executable // ""' "$support_json")"
  require_path_component "appName" "$app_name"
  require_path_component "executable" "$expected_executable"
  [[ -n $expected_bundle_id ]] || die "bundleId is missing for $package_id"

  app="$store_path/Applications/$app_name"
  plist="$app/Contents/Info.plist"
  [[ -d $app ]] || die "Nix app is unavailable: $app"
  [[ -f $plist ]] || die "Info.plist is unavailable: $plist"
  [[ -x $app/Contents/MacOS/$expected_executable ]] ||
    die "declared app executable is unavailable: $app/Contents/MacOS/$expected_executable"

  actual_bundle_id="$("$PLISTBUDDY_COMMAND" -c 'Print :CFBundleIdentifier' "$plist")"
  [[ $actual_bundle_id == "$expected_bundle_id" ]] ||
    die "CFBundleIdentifier mismatch for $package_id: expected $expected_bundle_id, got $actual_bundle_id"

  actual_executable="$("$PLISTBUDDY_COMMAND" -c 'Print :CFBundleExecutable' "$plist")"
  [[ $actual_executable == "$expected_executable" ]] ||
    die "CFBundleExecutable mismatch for $package_id: expected $expected_executable, got $actual_executable"

  "$CODESIGN_COMMAND" --verify --deep --strict "$app"
  source="$("$JQ_COMMAND" -r --arg id "$package_id" '.[$id].darwin.source // ""' "$support_json")"
  signature_details="$("$CODESIGN_COMMAND" --display --verbose=4 "$app" 2>&1 || true)"
  if [[ $source != "nixpkgs" || $signature_details != *"Signature=adhoc"* ]]; then
    "$SPCTL_COMMAND" --assess --type execute "$app"
  fi
  if ((launch == 1)); then
    "$OPEN_COMMAND" "$app"
  fi
  ;;
command)
  ((launch == 0)) || die "--launch is supported only for app identities"
  command_name="$("$JQ_COMMAND" -r --arg id "$package_id" '.[$id].darwin.identity.command // ""' "$support_json")"
  require_path_component "command" "$command_name"
  "$JQ_COMMAND" -e --arg id "$package_id" '.[$id].darwin.identity.versionArgs | type == "array"' "$support_json" >/dev/null ||
    die "versionArgs must be an array for $package_id"
  command_path="$store_path/bin/$command_name"
  [[ -x $command_path ]] || die "declared command is unavailable: $command_path"

  version_args=()
  while IFS= read -r -d '' version_arg; do
    version_args[${#version_args[@]}]="$version_arg"
  done < <("$JQ_COMMAND" -j --arg id "$package_id" '.[$id].darwin.identity.versionArgs[] | ., "\u0000"' "$support_json")
  if ((${#version_args[@]} > 0)); then
    "$command_path" "${version_args[@]}"
  else
    "$command_path"
  fi
  ;;
*) die "Darwin verification identity is missing for $package_id" ;;
esac
