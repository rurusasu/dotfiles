{ inputs }:
let
  pkgs = import inputs.nixpkgs {
    system = "aarch64-darwin";
    config.allowUnfree = true;
  };
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  retiredIds = [
    "GitHub.Copilot"
    "Microsoft.VisualStudioCode"
    "ZedIndustries.Zed"
    "SlackTechnologies.Slack"
    "SST.opencode"
  ];
  supportReportJson = builtins.toJSON sets.supportReport;
  absentFromMappings = id: {
    supportReport =
      builtins.replaceStrings [ id ] [ "" ] supportReportJson == supportReportJson;
    wingetMap = !(builtins.elem id (builtins.attrValues sets.wingetMap));
    msstoreMap = !(builtins.elem id (
      builtins.attrNames sets.msstoreMap ++ builtins.attrValues sets.msstoreMap
    ));
    npmMap = !(builtins.elem id (
      builtins.attrNames sets.npmMap ++ builtins.attrValues sets.npmMap
    ));
    pnpmGlobal = !(builtins.elem id sets.pnpmGlobal);
    windowsOnly = {
      winget = !(builtins.elem id sets.windowsOnly.winget);
      msstore = !(builtins.elem id sets.windowsOnly.msstore);
      npm = !(builtins.elem id sets.windowsOnly.npm);
      pnpm = !(builtins.elem id sets.windowsOnly.pnpm);
    };
  };
in
{
  testRetiredPackageIdsAreAbsentFromEvaluatedMappings = {
    expr = builtins.listToAttrs (
      map (id: {
        name = id;
        value = absentFromMappings id;
      }) retiredIds
    );
    expected = builtins.listToAttrs (
      map (id: {
        name = id;
        value = {
          supportReport = true;
          wingetMap = true;
          msstoreMap = true;
          npmMap = true;
          pnpmGlobal = true;
          windowsOnly = {
            winget = true;
            msstore = true;
            npm = true;
            pnpm = true;
          };
        };
      }) retiredIds
    );
  };
}
