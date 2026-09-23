{ inputs }:
let
  hostPackageNames = system:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
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
