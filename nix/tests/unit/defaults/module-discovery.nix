{ code, files }:
let
  discover = code.nix.discover-modules;
  root = files.nix.tests.fixtures.module-discovery.__path;
  relativePaths =
    scope:
    map (path: builtins.substring (builtins.stringLength (toString root) + 1) 1000 (toString path)) (
      discover scope root
    );
in
{
  testHomeModulesAreDiscoveredRecursivelyWithoutImportingFactories = {
    expr = relativePaths "home-manager";
    expected = [
      "app/default.nix"
      "app/nested/integration/default.nix"
    ];
  };
  testModuleDiscoverySeparatesEvaluationScopes = {
    expr = {
      nixos = relativePaths "nixos";
      darwin = relativePaths "darwin";
    };
    expected = {
      nixos = [ "app/nixos/default.nix" ];
      darwin = [ ];
    };
  };
}
