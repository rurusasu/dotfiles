# Generate windows/winget/packages.json, windows/npm/packages.json,
# and windows/pnpm/packages.json
# from the SSOT (sets.nix).
#
# Usage:
#   nix build .#winget-export
#   cp result/winget/packages.json windows/winget/packages.json
#   cp result/npm/packages.json windows/npm/packages.json
#   cp result/pnpm/packages.json windows/pnpm/packages.json
{
  pkgs,
  lib,
  codexPackage ? null,
}:
let
  sets = import ./sets.nix {
    inherit pkgs lib codexPackage;
  };

  # GUI-only installation selection is separate from cross-platform provider
  # availability. An unclassified package never enters Windows setup.
  guiCatalogMap = lib.filterAttrs (name: _: builtins.elem name sets.windowsGuiPackages.catalog);
  guiWindowsOnly = builtins.filter (id: builtins.elem id sets.windowsGuiPackages.windowsOnly);

  # Attach verifyCommand to a package object if defined in verifyMap
  attachVerify =
    verifyMap: key: pkg:
    let
      verify = verifyMap.${key} or null;
    in
    if verify == null then pkg else pkg // { verifyCommand = verify; };

  attachInstallArgs =
    installArgsMap: key: pkg:
    let
      installArgs = installArgsMap.${key} or null;
    in
    if installArgs == null then pkg else pkg // { inherit installArgs; };

  attachRequiresAdmin =
    requiresAdminMap: key: pkg:
    if requiresAdminMap.${key} or false then pkg // { requiresAdmin = true; } else pkg;

  attachInstallTimeout =
    installTimeoutMap: key: pkg:
    let
      # Only intentional per-package overrides belong in the manifest. The
      # generic install timeout is resolved by the runtime adapter so the
      # shared environment variable can override its default. Metadata is
      # attached in ID-then-catalog-key order, making the catalog key win.
      installTimeoutSeconds = installTimeoutMap.${key} or sets.packageInstallTimeoutSeconds;
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

  attachWingetMetadata =
    key: pkg:
    attachRequiresAdmin sets.wingetRequiresAdmin key (
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
      )
    );

  # Catalog migrations change metadata lookup from PackageIdentifier to the
  # catalog attr name. Apply the ID-keyed metadata as a fallback so generated
  # Windows verification and installer behavior remain compatible.
  attachWingetIdMetadata =
    id: pkg:
    attachRequiresAdmin sets.wingetRequiresAdmin id (
      attachSkipInstall sets.wingetSkipInstall id (
        attachCiSkipInstall sets.wingetCiSkipInstall id (
          attachPathEntries sets.wingetPathEntries id (
            attachPortableLink sets.wingetPortableLinksById id (
              attachDirectInstaller sets.wingetDirectInstallers id (
                attachInstallTimeout sets.wingetInstallTimeoutSeconds id (
                  attachInstallArgs sets.wingetInstallArgs id (attachVerify sets.wingetVerifyById id pkg)
                )
              )
            )
          )
        )
      )
    );

  # --- winget ---
  wingetFromMap = lib.mapAttrsToList (
    name: id: attachWingetMetadata name (attachWingetIdMetadata id { PackageIdentifier = id; })
  ) (guiCatalogMap sets.wingetMap);

  wingetFromWindowsOnly = map (
    id:
    attachRequiresAdmin sets.wingetRequiresAdmin id (
      attachSkipInstall sets.wingetSkipInstall id (
        attachCiSkipInstall sets.wingetCiSkipInstall id (
          attachPathEntries sets.wingetPathEntries id (
            attachPortableLink sets.wingetPortableLinksById id (
              attachDirectInstaller sets.wingetDirectInstallers id (
                attachInstallTimeout sets.wingetInstallTimeoutSeconds id (
                  attachInstallArgs sets.wingetInstallArgs id (
                    attachVerify sets.wingetVerifyById id { PackageIdentifier = id; }
                  )
                )
              )
            )
          )
        )
      )
    )
  ) (guiWindowsOnly sets.windowsOnly.winget);

  wingetPackages = wingetFromMap ++ wingetFromWindowsOnly;

  msstoreFromMap = lib.mapAttrsToList (
    name: id:
    attachSkipInstall sets.wingetSkipInstall name (
      attachCiSkipInstall sets.wingetCiSkipInstall name (
        attachSkipInstall sets.wingetSkipInstall id (
          attachCiSkipInstall sets.wingetCiSkipInstall id (
            attachInstallTimeout sets.wingetInstallTimeoutSeconds id (
              attachVerify sets.msstoreVerifyById id { PackageIdentifier = id; }
            )
          )
        )
      )
    )
  ) (guiCatalogMap sets.msstoreMap);

  msstorePackagesWindowsOnly = map (
    id:
    attachSkipInstall sets.wingetSkipInstall id (
      attachCiSkipInstall sets.wingetCiSkipInstall id (
        attachInstallTimeout sets.wingetInstallTimeoutSeconds id (
          attachVerify sets.msstoreVerifyById id { PackageIdentifier = id; }
        )
      )
    )
  ) (guiWindowsOnly sets.windowsOnly.msstore);

  msstorePackages = msstoreFromMap ++ msstorePackagesWindowsOnly;

  # Node CLI packages are deliberately excluded from Windows GUI setup.
  npmPackages = [ ];
  pnpmPackages = [ ];

  # --- outputs ---
  npmOutput = {
    "$schema" = "https://json.schemastore.org/package.json";
    description = "npm global packages to install on Windows";
    globalPackages = npmPackages;
  };

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
  npmJson = builtins.toJSON npmOutput;
  pnpmJson = builtins.toJSON pnpmOutput;

in
pkgs.runCommand "winget-export" { } ''
  mkdir -p $out/winget $out/npm $out/pnpm
  echo '${wingetJson}' | ${pkgs.jq}/bin/jq . > $out/winget/packages.json
  echo '${npmJson}' | ${pkgs.jq}/bin/jq . > $out/npm/packages.json
  echo '${pnpmJson}' | ${pkgs.jq}/bin/jq . > $out/pnpm/packages.json
  ${pkgs.oxfmt}/bin/oxfmt \
    $out/winget/packages.json \
    $out/npm/packages.json \
    $out/pnpm/packages.json
''
