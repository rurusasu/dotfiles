#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
entrypoint="$repo_root/docker/hermes-browser/entrypoint.sh"

for argument in \
  "--disable-background-timer-throttling" \
  "--disable-renderer-backgrounding" \
  "--disable-backgrounding-occluded-windows" \
  "--disable-features=CalculateNativeWinOcclusion,TabDiscarding"; do
  grep -Fq -- "$argument" "$entrypoint"
done

if grep -Fq -- "--disable-gpu" "$entrypoint"; then
  echo "Chrome GPU rendering must remain enabled" >&2
  exit 1
fi

python3 - "$repo_root/docker/hermes-browser-mcp/package.json" "$repo_root/docker/hermes-browser-mcp/package-lock.json" <<'PY'
import json
import sys
from pathlib import Path

package_path, lock_path = map(Path, sys.argv[1:])
package = json.loads(package_path.read_text(encoding="utf-8"))
expected = {
    "chrome-devtools-mcp": "1.6.0",
    "mcp-proxy": "6.5.5",
}
if package.get("dependencies") != expected:
    raise SystemExit(f"unexpected package dependencies: {package.get('dependencies')!r}")

lock = json.loads(lock_path.read_text(encoding="utf-8"))
for name, version in expected.items():
    dependency = lock["packages"][f"node_modules/{name}"]
    if dependency["version"] != version:
        raise SystemExit(f"unexpected lock version for {name}: {dependency['version']!r}")

print("Hermes browser runtime contracts: PASS")
PY
