# Compose installation metadata without evaluating platform package profiles.
{
  lib,
  pkgs,
  catalog,
  windowsOnly,
}:
let
  packageInstallTimeoutSeconds = 3600;
  terminalInstall = import ../../modules/terminals/wezterm/windows-install.nix;
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
// import ./node.nix { inherit packageInstallTimeoutSeconds; }
// (
  let
    base = import ./windows-verification.nix { inherit packageInstallTimeoutSeconds; };
  in
  base // { wingetVerify = base.wingetVerify // terminalInstall.wingetVerify; }
)
// (
  let
    base = import ./windows-install.nix { inherit packageInstallTimeoutSeconds; };
  in
  base // { wingetPathEntries = base.wingetPathEntries // terminalInstall.wingetPathEntries; }
)
