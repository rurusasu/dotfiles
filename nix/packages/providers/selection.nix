# Resolve platform providers and public package profiles.
{
  pkgs,
  lib,
  catalog,
  supports,
  platformKey,
}:
let
  grouped = lib.groupBy (name: catalog.${name}.category) (lib.attrNames catalog);
  isDarwinGuiNixPackage =
    entry:
    let
      darwinSupport = entry.support.darwin or { };
      identity = darwinSupport.identity or null;
    in
    (darwinSupport.provider or null) == "nix" && builtins.isAttrs identity && identity ? appName;

  # Resolve catalog IDs to Nix derivations selected for the current platform.
  resolveWhere =
    predicate: names:
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
          && predicate entry
          && package != null
          && supports package pkgs.stdenv.hostPlatform.system
        then
          package
        else
          null
      ) names
    );

  resolve = resolveWhere (_: true);

  darwinSystemPackages =
    if pkgs.stdenv.hostPlatform.isDarwin then
      resolveWhere isDarwinGuiNixPackage (lib.attrNames catalog)
    else
      [ ];

  darwinHomePackages =
    if pkgs.stdenv.hostPlatform.isDarwin then
      resolveWhere (entry: !isDarwinGuiNixPackage entry) (lib.attrNames catalog)
    else
      [ ];

  darwinCasks = lib.mapAttrsToList (_: entry: entry.support.darwin.cask or null) (
    lib.filterAttrs (
      _: entry:
      (entry.support.darwin.provider or null) == "homebrew-cask"
      && (entry.support.darwin.cask or null) != null
    ) catalog
  );
  darwinBrews = lib.mapAttrsToList (_: entry: entry.support.darwin.formula or null) (
    lib.filterAttrs (
      _: entry:
      (entry.support.darwin.provider or null) == "homebrew-formula"
      && (entry.support.darwin.formula or null) != null
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
  all = resolve (lib.attrNames catalog);
  allWithout =
    excludedNames:
    resolve (builtins.filter (name: !(builtins.elem name excludedNames)) (lib.attrNames catalog));
  # Host integrations such as Orca need GitHub CLI outside the user profile.
  hostPackages = resolve [ "gh" ];

  inherit
    resolve
    darwinSystemPackages
    darwinHomePackages
    darwinCasks
    darwinBrews
    darwinPackages
    ;
}
