{
  pkgs,
  lib,
  codexPackage,
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
  test "$(${pkgs.jq}/bin/jq length "$out/errors.json")" -eq 0
''
