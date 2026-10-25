{ inputs }:
{
  testNodejsIsNotInstalledAsAStandalonePackage = {
    expr = map (package: package.drvPath) (
      builtins.filter (package: (package.pname or null) == "nodejs")
        ((import ../fixtures/packages.nix { inherit inputs; }).mkHome "x86_64-linux" [
          (import ../../default.nix { }).homeModules.common
          ../../modules/editors/nvim
        ]).config.home.packages
    );
    expected = [ ];
  };
}
