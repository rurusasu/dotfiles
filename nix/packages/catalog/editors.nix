# Package identities and provider declarations for editors.
{ pkgs, ... }:
{
  neovim = {
    pkg = pkgs.neovim;
    winget = "Neovim.Neovim";
    category = "editors";
  };

  neovim-remote = {
    pkg = pkgs.neovim-remote;
    winget = null;
    category = "editors";
  };

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
          homepage = "https://obsidian.md/";
          appName = "Obsidian.app";
          bundleId = "md.obsidian";
          executable = "Obsidian";
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
