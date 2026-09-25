{ inputs }:
let
  fixtures = import ../test-fixtures.nix { inherit inputs; };
  hostPackageNames =
    system:
    let
      pkgs = fixtures.mkPkgs system;
      sets = import ../packages/sets.nix {
        inherit pkgs;
        inherit (pkgs) lib;
        codexPackage = pkgs.hello;
      };
    in
    builtins.map (package: package.pname or package.name) sets.hostPackages;
in
{
  testHostPackageSetIncludesGitHubCliForDarwinAndLinux = {
    expr = {
      darwin = builtins.elem "gh" (hostPackageNames "aarch64-darwin");
      linux = builtins.elem "gh" (hostPackageNames "x86_64-linux");
    };
    expected = {
      darwin = true;
      linux = true;
    };
  };
}
