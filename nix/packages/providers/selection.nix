# Resolve install features, platform providers, and public package profiles.
{
  pkgs,
  lib,
  catalog,
  supports,
  platformKey,
}:
let
  grouped = lib.groupBy (name: catalog.${name}.category) (lib.attrNames catalog);
  featureEnabled =
    enabledFeatures: entry:
    !(entry ? installFeature)
    || entry.installFeature == null
    || enabledFeatures == null
    || builtins.elem entry.installFeature enabledFeatures;

  isDarwinGuiNixPackage =
    entry:
    let
      darwinSupport = entry.support.darwin or { };
      identity = darwinSupport.identity or null;
    in
    (darwinSupport.provider or null) == "nix" && builtins.isAttrs identity && identity ? appName;

  # Resolve catalog IDs to Nix derivations selected for the current platform.
  resolveForInstallFeaturesWhere =
    enabledFeatures: predicate: names:
    builtins.filter (p: p != null) (
      map (
        name:
        let
          entry = catalog.${name};
          package = entry.pkg or null;
          provider = entry.support.${platformKey}.provider or null;
        in
        if
          provider == "nix"
          && featureEnabled enabledFeatures entry
          && predicate entry
          && package != null
          && supports package pkgs.stdenv.hostPlatform.system
        then
          package
        else
          null
      ) names
    );

  resolveForInstallFeatures =
    enabledFeatures: resolveForInstallFeaturesWhere enabledFeatures (_: true);

  # Default package outputs contain only packages without an opt-in feature.
  # Feature profiles use allForInstallFeatures or the platform-specific
  # resolvers below with an explicit feature list.
  resolve = resolveForInstallFeatures [ ];

  darwinSystemPackagesForInstallFeatures =
    enabledFeatures:
    if pkgs.stdenv.hostPlatform.isDarwin then
      resolveForInstallFeaturesWhere enabledFeatures isDarwinGuiNixPackage (lib.attrNames catalog)
    else
      [ ];

  darwinHomePackagesForInstallFeatures =
    enabledFeatures:
    if pkgs.stdenv.hostPlatform.isDarwin then
      resolveForInstallFeaturesWhere enabledFeatures (
        entry: !isDarwinGuiNixPackage entry && entry.category != "fonts"
      ) (lib.attrNames catalog)
    else
      [ ];

  darwinCasks = lib.mapAttrsToList (_: entry: entry.support.darwin.cask or null) (
    lib.filterAttrs (
      _: entry:
      (entry.support.darwin.provider or null) == "homebrew-cask"
      && (entry.support.darwin.cask or null) != null
    ) catalog
  );
  darwinCasksForInstallFeatures =
    enabledFeatures:
    lib.mapAttrsToList (_: entry: entry.support.darwin.cask or null) (
      lib.filterAttrs (
        _: entry:
        (entry.support.darwin.provider or null) == "homebrew-cask"
        && (entry.support.darwin.cask or null) != null
        && featureEnabled enabledFeatures entry
      ) catalog
    );
  darwinBrews = lib.mapAttrsToList (_: entry: entry.support.darwin.formula or null) (
    lib.filterAttrs (
      _: entry:
      (entry.support.darwin.provider or null) == "homebrew-formula"
      && (entry.support.darwin.formula or null) != null
    ) catalog
  );
  linuxSystemModules = lib.mapAttrsToList (_: entry: entry.support.linux.systemModule or null) (
    lib.filterAttrs (
      _: entry:
      (entry.support.linux.provider or null) == "system-manager"
      && (entry.support.linux.systemModule or null) != null
    ) catalog
  );
  darwinPackage =
    name: entry:
    let
      support = entry.support.darwin;
      inherit (support) provider;
    in
    if provider == "nix" then
      entry.pkg
    else
      pkgs.writeText "darwin-${name}-provider.json" (
        builtins.toJSON {
          inherit provider;
          inherit (support) source;
          inherit (support) identity;
        }
      );
  darwinPackages = lib.mapAttrs darwinPackage (
    lib.filterAttrs (
      _: entry:
      let
        provider = entry.support.darwin.provider or null;
      in
      if provider == "nix" then
        (entry.pkg or null) != null && supports entry.pkg pkgs.stdenv.hostPlatform.system
      else
        builtins.elem provider [
          "homebrew-cask"
          "homebrew-formula"
        ]
    ) catalog
  );

in
lib.mapAttrs (_: resolve) grouped
// {
  # All packages (flat list)
  all = resolveForInstallFeatures null (lib.attrNames catalog);
  allForInstallFeatures =
    enabledFeatures: resolveForInstallFeatures enabledFeatures (lib.attrNames catalog);
  allWithout =
    excludedNames:
    resolveForInstallFeatures null (
      builtins.filter (name: !(builtins.elem name excludedNames)) (lib.attrNames catalog)
    );
  allWithoutForInstallFeatures =
    enabledFeatures: excludedNames:
    resolveForInstallFeatures enabledFeatures (
      builtins.filter (name: !(builtins.elem name excludedNames)) (lib.attrNames catalog)
    );

  # Host integrations such as Orca need GitHub CLI outside the user profile.
  hostPackages = resolve [ "gh" ];

  inherit
    resolveForInstallFeatures
    darwinSystemPackagesForInstallFeatures
    darwinHomePackagesForInstallFeatures
    darwinCasks
    darwinCasksForInstallFeatures
    darwinBrews
    darwinPackages
    linuxSystemModules
    ;
}
