let
  defaults = import ../../../default.nix { };
  nixFiles =
    directory:
    builtins.filter (name: builtins.match ".*[.]nix" name != null) (
      builtins.attrNames (builtins.readDir directory)
    );
in
{
  testHostAndHomeDefinitionsAreConsolidated = {
    expr = {
      defaultsPresent = builtins.pathExists ../../../default.nix;
      hostFiles = nixFiles ../../../hosts;
      homeFiles = nixFiles ../../../home;
    };
    expected = {
      defaultsPresent = true;
      hostFiles = [ ];
      homeFiles = [ ];
    };
  };
  testDefaultsExposeSystemAndHomeModuleScopes = {
    expr = {
      systems = builtins.attrNames defaults.hostModules;
      homes = builtins.attrNames defaults.homeModules;

    };
    expected = {
      systems = [
        "darwin"
        "linux"
        "nixos"
        "wsl"
      ];
      homes = [
        "common"
        "darwin"
        "linux"
        "wsl"
      ];
    };
  };
}
