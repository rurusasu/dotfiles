{
  pkgs,
  lib,
  gwqSrc ? null,
}:
let
  sets = import ./sets.nix { inherit pkgs lib gwqSrc; };
  reportFile = pkgs.writeText "package-support.json" (builtins.toJSON sets.supportReport);
  errorsFile = pkgs.writeText "package-provider-errors.json" (builtins.toJSON sets.providerErrors);
in
pkgs.runCommand "package-support-report" { } ''
  mkdir -p "$out"
  ${pkgs.jq}/bin/jq . ${reportFile} > "$out/support.json"
  ${pkgs.jq}/bin/jq . ${errorsFile} > "$out/errors.json"
  test "$(${pkgs.jq}/bin/jq length "$out/errors.json")" -eq 0
''
