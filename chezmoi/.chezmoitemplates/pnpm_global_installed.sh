GLOBAL_PACKAGES_JSON='[]'
if ! GLOBAL_PACKAGES_JSON="$(pnpm list -g --depth=0 --json 2>/dev/null)"; then
  GLOBAL_PACKAGES_JSON='[]'
fi

pnpm_global_package_installed() {
  PNPM_GLOBAL_PACKAGES_JSON="$GLOBAL_PACKAGES_JSON" \
    PNPM_GLOBAL_PACKAGE="$1" \
    node <<'NODE'
const packageName = process.env.PNPM_GLOBAL_PACKAGE;
let roots;

try {
  roots = JSON.parse(process.env.PNPM_GLOBAL_PACKAGES_JSON || "[]");
} catch {
  process.exit(1);
}

if (!Array.isArray(roots)) {
  roots = [roots];
}

const installed = roots.some((root) => {
  const dependencies = root && typeof root === "object" ? root.dependencies : null;
  return dependencies && Object.prototype.hasOwnProperty.call(dependencies, packageName);
});

process.exit(installed ? 0 : 1);
NODE
}
