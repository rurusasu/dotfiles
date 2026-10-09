#!/usr/bin/env bash
set -euo pipefail

sandbox=false
if [[ ${1:-} == --sandbox && $# -eq 1 ]]; then
  sandbox=true
elif [[ $# -ne 0 ]]; then
  echo "Usage: $0 [--sandbox]" >&2
  exit 64
fi

for tool in bash bats chezmoi git git-lfs jq nix node ps python3 pwsh ruby statix tar task xz; do
  if ! command -v "$tool" >/dev/null; then
    echo "Missing bootstrap CI tool: $tool" >&2
    exit 1
  fi
done

bash -lc 'command -v git >/dev/null && command -v nix >/dev/null'

python3 -c 'import sys; assert sys.version_info >= (3, 14), sys.version'
node -e 'if (Number(process.versions.node.split(".")[0]) < 24) process.exit(1)'
nix eval --json --expr '1 + 1' | grep -qx 2
nix store info --store local

# PowerShell expands these variables.
# shellcheck disable=SC2016
pwsh -NoLogo -NoProfile -Command '
  $ErrorActionPreference = "Stop"
  Import-Module PSScriptAnalyzer -Force
  $formatted = Invoke-Formatter -ScriptDefinition "function Test-Example{Get-Date}"
  if ([string]::IsNullOrWhiteSpace($formatted)) { throw "PowerShell formatter returned no output" }
'

fixture=$(mktemp -d)
trap 'rm -r "$fixture"' EXIT
printf '{ value = 1; }\n' >"$fixture/default.nix"
statix check "$fixture"
printf 'true == true\n' >"$fixture/default.nix"
if statix check "$fixture" >"$fixture/statix.log" 2>&1; then
  echo "statix did not reject the invalid fixture" >&2
  exit 1
fi

if [[ $sandbox == true ]]; then
  CI_BASH=$(readlink -f "$(command -v bash)")
  export CI_BASH
  # Nix expands $out inside the builder shell.
  # shellcheck disable=SC2016
  nix build --impure --no-link --expr 'derivation {
    name = "bootstrap-ci-sandbox";
    system = "x86_64-linux";
    builder = builtins.storePath (builtins.getEnv "CI_BASH");
    args = [ "-c" "echo sandbox-ok > $out" ];
  }'
fi

echo "Bootstrap CI tools verified."
