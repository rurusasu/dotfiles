let
  discover = import ../../../discover-modules.nix;
  root = ../../fixtures/module-discovery;
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
      "app/home-manager.nix"
      "app/nested/integration.home-manager.nix"
    ];
  };
  testModuleDiscoverySeparatesEvaluationScopes = {
    expr = {
      nixos = relativePaths "nixos";
      darwin = relativePaths "darwin";
    };
    expected = {
      nixos = [ "app/nixos.nix" ];
      darwin = [ ];
    };
  };
}
