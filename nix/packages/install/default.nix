# Compose installation metadata without evaluating platform package profiles.
{
  lib,
  catalog,
  windowsOnly,
}:
let
  packageInstallTimeoutSeconds = 900;
  # Extract winget mappings (non-null only)
  wingetMap = lib.filterAttrs (_: v: v != null) (lib.mapAttrs (_: v: v.winget or null) catalog);
  wingetFeatureMap = lib.filterAttrs (_: v: v != null) (
    lib.mapAttrs (_: v: v.installFeature or null) catalog
  );
  msstoreMap = lib.filterAttrs (_: v: v != null) (lib.mapAttrs (_: v: v.msstore or null) catalog);
  npmMap = lib.filterAttrs (_: v: v != null) (lib.mapAttrs (_: v: v.npm or null) catalog);

in
{
  inherit
    wingetMap
    wingetFeatureMap
    msstoreMap
    npmMap
    ;
  inherit (windowsOnly) windowsOnlySupport windowsOnly;
}
// import ./node.nix
// import ./windows-verification.nix { inherit packageInstallTimeoutSeconds; }
// import ./windows-install.nix { inherit packageInstallTimeoutSeconds; }
