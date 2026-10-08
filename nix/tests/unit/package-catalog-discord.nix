{ inputs }:
let
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
in
{
  testDiscordPreservesWindowsModuleDistribution = {
    expr = sets.supportReport."Discord.Discord";
    expected = {
      installFeature = null;
      windows = {
        provider = "winget";
        source = "winget";
        identity = "Discord.Discord";
      };
      linux.unsupported = "Unix installation is owned by the Discord Home Manager module";
      darwin.unsupported = "Unix installation is owned by the Discord Home Manager module";
    };
  };
}
