{ inputs }:
let
  system = "aarch64-darwin";
  pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
  Workmux = import ../flakes/lib/workmux.nix { inherit inputs; };
  workmuxOverlay = Workmux.mkOverlay (_: inputs.workmux.packages.${system}.default);
  catalogPkgs = pkgs.extend workmuxOverlay;
  codexPackage = inputs.llm-agents.packages.${system}.codex;
  sets = import ../packages/sets.nix {
    pkgs = catalogPkgs;
    lib = pkgs.lib;
    inherit codexPackage;
  };
  expectedTartMinimal = pkgs.buildEnv {
    name = "dotfiles-tart-minimal";
    paths = sets.tartMinimal;
  };
in
{
  testTartMinimalContainsOnlyRequestedCliPackages = {
    expr = map pkgs.lib.getName sets.tartMinimal;
    expected = [ "git" "chezmoi" "neovim" "codex" ];
  };

  testTartMinimalOutputIsBuiltFromResolvedPackageSet = {
    expr = inputs.self.packages.${system}."tart-minimal".drvPath;
    expected = expectedTartMinimal.drvPath;
  };

  testTartCatalogUsesResolvedNixPackageAndRetainsDarwinMigrationMetadata = {
    expr = {
      resolvedPackage = sets.darwinPackages.tart.drvPath;
      provider = sets.supportReport.tart.darwin.provider;
      source = sets.supportReport.tart.darwin.source;
      nixAttr = sets.supportReport.tart.darwin.nixAttr;
      identity = sets.supportReport.tart.darwin.identity;
      command = sets.supportReport.tart.darwin.identity.command;
      legacyDarwin = sets.supportReport.tart.legacyDarwin;
    };
    expected = {
      resolvedPackage = pkgs.tart.drvPath;
      provider = "nix";
      source = "nixpkgs";
      nixAttr = "tart";
      identity = {
        homepage = "https://tart.run/";
        command = "tart";
        versionArgs = [ "--version" ];
      };
      command = "tart";
      legacyDarwin = {
        provider = "homebrew-formula";
        name = "openai/tools/tart";
      };
    };
  };
}
