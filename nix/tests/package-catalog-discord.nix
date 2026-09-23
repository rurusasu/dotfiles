{ inputs }:
let
  pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
in
{
  testDiscordPreservesProvidersAndDarwinMigration = {
    expr = sets.supportReport.discord;
    expected = {
      installFeature = null;
      windows = {
        provider = "winget";
        source = "winget";
        identity = "Discord.Discord";
      };
      linux = {
        provider = "nix";
        source = "nixpkgs";
        identity = "discord";
        nixAttr = "discord";
      };
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        identity = {
          homepage = "https://discord.com/";
          appName = "Discord.app";
          bundleId = "com.hnc.Discord";
          executable = "Discord";
        };
        nixAttr = "discord";
      };
      legacyDarwin = {
        provider = "homebrew-cask";
        name = "discord";
      };
    };
  };
}
