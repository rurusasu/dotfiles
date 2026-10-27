{ inputs }:
let
  repository = import ./source-tree.nix inputs.self.outPath;
  inherit (repository) code files;
  fixtures = code.nix.tests.fixtures.packages { inherit inputs; };
  homeConfigurations = code.nix.tests.fixtures.home-configurations { inherit inputs; };
  upstream = builtins.mapAttrs (_: input: import ./source-tree.nix input.outPath) (
    inputs.nixpkgs.lib.filterAttrs (_: input: input ? inputs) inputs
  );
in
{
  inherit
    inputs
    fixtures
    homeConfigurations
    code
    files
    upstream
    ;
}
