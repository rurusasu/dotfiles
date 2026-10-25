let
  defaults = import ../../../defaults.nix { };
  nixFiles =
    directory:
    builtins.filter (name: builtins.match ".*[.]nix" name != null) (
      builtins.attrNames (builtins.readDir directory)
    );
in
{
  testHostAndHomeDefinitionsAreConsolidated = {
    expr = {
      defaultsPresent = builtins.pathExists ../../../defaults.nix;
      hostFiles = nixFiles ../../../hosts;
      homeFiles = nixFiles ../../../home;
    };
    expected = {
      defaultsPresent = true;
      hostFiles = [ ];
      homeFiles = [ ];
    };
  };
  testDefaultsUseSystemModulesAndSharedHomeManagerDefaults = {
    expr = {
      sharedSystem = builtins.isFunction defaults.systemDefaults;
      separateHosts = defaults ? hostModules;
      separateHomes = defaults ? homeModules;
      sharedHomes =
        builtins.isList
          (defaults.systemDefaults {
            inputs = { };
            pkgs = { };
            platform = "linux";
          }).home-manager.sharedModules;

    };
    expected = {
      sharedSystem = true;
      separateHosts = false;
      separateHomes = false;
      sharedHomes = true;
    };
  };
}
