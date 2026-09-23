{ inputs }:
let
  system = "aarch64-darwin";
  pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  support = sets.supportReport.docker-desktop;
in
{
  testDockerProviderMetadataAndFeatureSelectedCask = {
    expr = {
      installFeature = support.installFeature;
      windows = {
        inherit (support.windows) provider source identity;
      };
      darwin = {
        inherit (support.darwin) provider source identity cask;
      };
      linux = {
        inherit (support.linux) provider source identity systemModule;
      };
      legacyDarwin = support.legacyDarwin;
      defaultCaskExcluded = !(
        builtins.elem "docker-desktop" (sets.darwinCasksForInstallFeatures [ ])
      );
      dockerCaskSelected = builtins.elem "docker-desktop" (
        sets.darwinCasksForInstallFeatures [ "WithOllama" "WithDocker" ]
      );
    };
    expected = {
      installFeature = "WithDocker";
      windows = {
        provider = "winget";
        source = "winget";
        identity = "Docker.DockerDesktop";
      };
      darwin = {
        provider = "homebrew-cask";
        source = "homebrew";
        identity = "docker-desktop";
        cask = "docker-desktop";
      };
      linux = {
        provider = "system-manager";
        source = "nixpkgs";
        identity = "docker";
        systemModule = "docker";
      };
      legacyDarwin = null;
      defaultCaskExcluded = true;
      dockerCaskSelected = true;
    };
  };
}
