{
  pkgs,
  lib,
  codexPackage ? null,
}:
let
  sets = import ./sets.nix {
    inherit pkgs lib codexPackage;
  };
  reportFile = pkgs.writeText "package-support.json" (builtins.toJSON sets.supportReport);
  darwinPackagesFile = pkgs.writeText "darwin-packages.json" (
    builtins.toJSON (builtins.attrNames sets.darwinPackages)
  );
  errorsFile = pkgs.writeText "package-provider-errors.json" (builtins.toJSON sets.providerErrors);
in
pkgs.runCommand "package-support-report" { } ''
  mkdir -p "$out"
  ${pkgs.jq}/bin/jq . ${reportFile} > "$out/support.json"
  ${pkgs.jq}/bin/jq . ${darwinPackagesFile} > "$out/darwin-packages.json"
  ${pkgs.jq}/bin/jq . ${errorsFile} > "$out/errors.json"
  error_count="$(${pkgs.jq}/bin/jq length "$out/errors.json")"
  if [ "$error_count" -gt 0 ]; then
    echo "package-support-report: expected zero provider errors; found $error_count:" >&2
    ${pkgs.jq}/bin/jq -r '.[]' "$out/errors.json" >&2
  fi
  test "$error_count" -eq 0
''
