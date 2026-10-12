{ inputs }:
let
  fixtures = import ../fixtures/packages.nix { inherit inputs; };
  home = fixtures.mkHome "aarch64-darwin" [ ../../hosts/aarch64-darwin/home.nix ];
in
{
  testCodexCliIsNotIndependentlyInstalled = {
    expr = {
      managed = home.config.programs.codex.enable;
      npmProvider = home.config.programs.codex.package == null;
      duplicatePackage = builtins.any (
        package: (package.pname or "") == "codex"
      ) home.config.home.packages;
    };
    expected = {
      managed = true;
      npmProvider = true;
      duplicatePackage = false;
    };
  };
}
