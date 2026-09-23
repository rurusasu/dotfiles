{ inputs }:
let
  system = "aarch64-darwin";
  pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [ (_: _: { workmux = inputs.workmux.packages.${system}.default; }) ];
  };
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = inputs.llm-agents.packages.${system}.codex;
  };
  hermesSupport = sets.supportReport.hermes-desktop;
in
{
  testHermesDesktopCaskSupportMetadataAndDefaultExclusion = {
    expr = {
      installFeature = hermesSupport.installFeature;
      darwinSupport = hermesSupport.darwin;
      excludedFromDefaultCasks = !(
        builtins.elem "hermes-desktop" (sets.darwinCasksForInstallFeatures [ ])
      );
      includedWithHermes = builtins.elem "hermes-desktop" (
        sets.darwinCasksForInstallFeatures [ "WithHermes" ]
      );
    };
    expected = {
      installFeature = "WithHermes";
      darwinSupport = {
        provider = "homebrew-cask";
        source = "homebrew";
        identity = "hermes-desktop";
        cask = "hermes-desktop";
      };
      excludedFromDefaultCasks = true;
      includedWithHermes = true;
    };
  };
}
