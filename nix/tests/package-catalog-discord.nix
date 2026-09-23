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
