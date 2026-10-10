# Compose installation metadata without evaluating platform package profiles.
{
  lib,
  catalog,
  windowsOnly,
  ...
}:
let
  packageInstallTimeoutSeconds = 3600;
  onepasswordInstall = import ../../modules/1password/windows-install.nix;
  gitInstall = import ../../modules/git/windows-install.nix;
  discordInstall = import ../../modules/discord/windows-install.nix;
  lazygitInstall = import ../../modules/lazygit/windows-install.nix;
  starshipInstall = import ../../modules/starship/windows-install.nix;
  terminalInstall = import ../../modules/terminals/wezterm/windows-install.nix;
  chatgptInstall = import ../../modules/ai_agents/chatgpt/windows-install.nix;
  # Extract winget mappings (non-null only)
  wingetMap = lib.filterAttrs (_: v: v != null) (lib.mapAttrs (_: v: v.winget or null) catalog);
  msstoreMap = lib.filterAttrs (_: v: v != null) (lib.mapAttrs (_: v: v.msstore or null) catalog);
  npmMap = lib.filterAttrs (_: v: v != null) (lib.mapAttrs (_: v: v.npm or null) catalog);

in
{
  inherit
    wingetMap
    msstoreMap
    npmMap
    ;
  inherit (windowsOnly) windowsOnlySupport windowsOnly;
}
// import ./node.nix
// (
  let
    base = import ./windows-verification.nix { inherit packageInstallTimeoutSeconds; };
  in
  base
  // {
    wingetVerify = base.wingetVerify // terminalInstall.wingetVerify;
    msstoreVerifyById = base.msstoreVerifyById // chatgptInstall.msstoreVerifyById;
    wingetVerifyById =
      base.wingetVerifyById
      // discordInstall.wingetVerifyById
      // starshipInstall.wingetVerifyById
      // lazygitInstall.wingetVerifyById
      // onepasswordInstall.wingetVerifyById
      // gitInstall.wingetVerifyById;
  }
)
// (
  let
    base = import ./windows-install.nix { inherit packageInstallTimeoutSeconds; };
  in
  base
  // {
    wingetInstallArgs = base.wingetInstallArgs // onepasswordInstall.wingetInstallArgs;
    wingetCiSkipInstall = base.wingetCiSkipInstall // chatgptInstall.wingetCiSkipInstall;
    wingetPathEntries =
      base.wingetPathEntries // terminalInstall.wingetPathEntries // onepasswordInstall.wingetPathEntries;
  }
)
