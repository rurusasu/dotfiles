# Package identities and provider declarations for editors.
{ pkgs, ... }:
{
  obsidian = {
    pkg = pkgs.obsidian;
    winget = "Obsidian.Obsidian";
    category = "editors";
    support = {
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "obsidian";
        identity = {
          appName = "Obsidian.app";
        };
      };
      linux = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "obsidian";
        identity = "obsidian";
      };
    };
  };
}
