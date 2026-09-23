{ inputs }:
let
  pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
    catalogOverride = {
      hermes-desktop = {
        pkg = pkgs.hello;
        category = "terminal";
        installFeature = "WithHermes";
        support.darwin = {
          provider = "nix";
          source = "hermes-agent";
          identity.command = "hermes-desktop";
        };
      };
      base = {
        pkg = pkgs.cowsay;
        category = "terminal";
        support.darwin = {
          provider = "nix";
          source = "nixpkgs";
          identity = "cowsay";
        };
      };
    };
  };
in
{
  testHermesDesktopIsAbsentFromDefaultPackageOutputs = {
    expr = {
      default = builtins.elem pkgs.hello sets.terminal;
      withHermes = builtins.elem pkgs.hello (sets.allForInstallFeatures [ "WithHermes" ]);
    };
    expected = {
      default = false;
      withHermes = true;
    };
  };
}
