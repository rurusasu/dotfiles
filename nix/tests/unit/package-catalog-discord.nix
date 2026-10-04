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
  testDiscordPreservesProvidersAndDarwinIdentity = {
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
          appName = "Discord.app";
        };
        nixAttr = "discord";
      };
    };
  };
}
