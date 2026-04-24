# Generate windows/winget/packages.json from the SSOT (sets.nix).
#
# Usage:
#   nix build .#winget-export
#   cp result windows/winget/packages.json
{ pkgs, lib }:
let
  sets = import ./sets.nix { inherit pkgs lib; };

  wingetPackages =
    (lib.mapAttrsToList (_: id: { PackageIdentifier = id; }) sets.wingetMap)
    ++ (map (id: { PackageIdentifier = id; }) sets.windowsOnly.winget);

  msstorePackages = map (id: { PackageIdentifier = id; }) sets.windowsOnly.msstore;

  pnpmOutput = {
    "$schema" = "https://json.schemastore.org/package.json";
    description = "pnpm global packages to install on Windows";
    globalPackages = sets.pnpmGlobal ++ sets.windowsOnly.pnpm;
  };

  wingetOutput = {
    "$schema" = "https://aka.ms/winget-packages.schema.2.0.json";
    Sources = [
      {
        Packages = wingetPackages;
        SourceDetails = {
          Argument = "https://cdn.winget.microsoft.com/cache";
          Identifier = "Microsoft.Winget.Source_8wekyb3d8bbwe";
          Name = "winget";
          Type = "Microsoft.PreIndexed.Package";
        };
      }
    ]
    ++ lib.optionals (msstorePackages != [ ]) [
      {
        Packages = msstorePackages;
        SourceDetails = {
          Argument = "https://storeedgefd.dsx.mp.microsoft.com/v9.0";
          Identifier = "StoreEdgeFD";
          Name = "msstore";
          Type = "Microsoft.Rest";
        };
      }
    ];
  };

  wingetJson = builtins.toJSON wingetOutput;
  pnpmJson = builtins.toJSON pnpmOutput;

in
pkgs.runCommand "winget-export" { } ''
  mkdir -p $out/winget $out/pnpm
  echo '${wingetJson}' | ${pkgs.jq}/bin/jq . > $out/winget/packages.json
  echo '${pnpmJson}' | ${pkgs.jq}/bin/jq . > $out/pnpm/packages.json
''
