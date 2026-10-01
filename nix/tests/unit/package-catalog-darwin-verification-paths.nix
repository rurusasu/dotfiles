{ inputs }:
let
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  optionalPackage = pkgs.runCommand "optional-verification-fixture" { } "mkdir -p $out";
  paths = import ../../packages/install/darwin-paths.nix {
    darwinPackages = {
      current = pkgs.hello;
      optional = optionalPackage;
    };
  };
in
{
  testDarwinVerificationInventoryPreservesExactOutputPaths = {
    expr = paths;
    expected = {
      current = pkgs.hello.outPath;
      optional = optionalPackage.outPath;
    };
  };

  testDarwinVerificationInventoryDoesNotRealizeOptionalProviders = {
    expr = builtins.mapAttrs (_: path: builtins.getContext path) paths;
    expected = {
      current = { };
      optional = { };
    };
  };
}
