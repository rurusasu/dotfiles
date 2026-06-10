# Generate windows/winget/packages.json and windows/pnpm/packages.json
# from the SSOT (sets.nix).
#
# Usage:
#   nix build .#winget-export
#   cp result/winget/packages.json windows/winget/packages.json
#   cp result/pnpm/packages.json windows/pnpm/packages.json
{
  pkgs,
  lib,
  gwqSrc ? null,
}:
let
  sets = import ./sets.nix { inherit pkgs lib gwqSrc; };

  # Attach verifyCommand to a package object if defined in verifyMap
  attachVerify =
    verifyMap: key: pkg:
    let
      verify = verifyMap.${key} or null;
    in
    if verify == null then
      pkg
    else
      pkg
      // {
        verifyCommand = {
          inherit (verify) command args;
        }
        // lib.optionalAttrs (verify ? type) { inherit (verify) type; }
        // lib.optionalAttrs (verify ? timeoutSeconds) { inherit (verify) timeoutSeconds; }
        // lib.optionalAttrs (verify ? recoveryStrategy) {
          inherit (verify) recoveryStrategy;
        };
      };

  attachInstallArgs =
    installArgsMap: key: pkg:
    let
      installArgs = installArgsMap.${key} or null;
    in
    if installArgs == null then pkg else pkg // { inherit installArgs; };

  attachInstallTimeout =
    installTimeoutMap: key: pkg:
    let
      installTimeoutSeconds = installTimeoutMap.${key} or null;
    in
    if installTimeoutSeconds == null then pkg else pkg // { inherit installTimeoutSeconds; };

  attachDirectInstaller =
    directInstallersMap: key: pkg:
    let
      directInstaller = directInstallersMap.${key} or null;
    in
    if directInstaller == null then pkg else pkg // { inherit directInstaller; };

  attachSkipInstall =
    skipInstallMap: key: pkg:
    let
      skipReason = skipInstallMap.${key} or null;
    in
    if skipReason == null then
      pkg
    else
      pkg
      // {
        skipInstall = true;
        inherit skipReason;
      };

  attachCiSkipInstall =
    ciSkipInstallMap: key: pkg:
    let
      ciSkipInstall = ciSkipInstallMap.${key} or false;
    in
    if ciSkipInstall then pkg // { inherit ciSkipInstall; } else pkg;

  attachPortableLink =
    portableLinksMap: key: pkg:
    let
      portableLink = portableLinksMap.${key} or null;
    in
    if portableLink == null then pkg else pkg // { inherit portableLink; };

  attachPathEntries =
    pathEntriesMap: key: pkg:
    let
      pathEntries = pathEntriesMap.${key} or null;
    in
    if pathEntries == null then pkg else pkg // { inherit pathEntries; };

  attachPnpmInstallArgs =
    installArgsMap: key: pkg:
    let
      installArgs = installArgsMap.${key} or null;
    in
    if installArgs == null then pkg else pkg // { inherit installArgs; };

  attachWingetMetadata =
    key: pkg:
    attachSkipInstall sets.wingetSkipInstall key (
      attachCiSkipInstall sets.wingetCiSkipInstall key (
        attachPathEntries sets.wingetPathEntries key (
          attachPortableLink sets.wingetPortableLinksById key (
            attachDirectInstaller sets.wingetDirectInstallers key (
              attachInstallTimeout sets.wingetInstallTimeoutSeconds key (
                attachInstallArgs sets.wingetInstallArgs key (attachVerify sets.wingetVerify key pkg)
              )
            )
          )
        )
      )
    );

  # --- winget ---
  wingetFromMap = lib.mapAttrsToList (
    name: id: attachWingetMetadata name { PackageIdentifier = id; }
  ) sets.wingetMap;

  wingetFromWindowsOnly = map (
    id:
    attachSkipInstall sets.wingetSkipInstall id (
      attachCiSkipInstall sets.wingetCiSkipInstall id (
        attachPathEntries sets.wingetPathEntries id (
          attachPortableLink sets.wingetPortableLinksById id (
            attachDirectInstaller sets.wingetDirectInstallers id (
              attachVerify sets.wingetVerifyById id { PackageIdentifier = id; }
            )
          )
        )
      )
    )
  ) sets.windowsOnly.winget;

  wingetPackages = wingetFromMap ++ wingetFromWindowsOnly;

  msstorePackages = map (
    id:
    attachSkipInstall sets.wingetSkipInstall id (
      attachCiSkipInstall sets.wingetCiSkipInstall id (
        attachVerify sets.msstoreVerifyById id { PackageIdentifier = id; }
      )
    )
  ) sets.windowsOnly.msstore;

  # --- pnpm ---
  pnpmFromGlobal = map (
    name:
    attachPnpmInstallArgs sets.pnpmInstallArgs name (
      attachVerify sets.pnpmVerify name { inherit name; }
    )
  ) sets.pnpmGlobal;

  pnpmFromWindowsOnly = map (
    name:
    attachPnpmInstallArgs sets.pnpmInstallArgs name (
      attachVerify sets.pnpmVerify name { inherit name; }
    )
  ) sets.windowsOnly.pnpm;

  pnpmPackages = pnpmFromGlobal ++ pnpmFromWindowsOnly;

  # --- outputs ---
  pnpmOutput = {
    "$schema" = "https://json.schemastore.org/package.json";
    description = "pnpm global packages to install on Windows";
    globalPackages = pnpmPackages;
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
