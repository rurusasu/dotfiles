let
  defaults = import ../../../default.nix { };
  host = defaults.hostModules.darwin {
    pkgs = { };
    inputs = { };
    sudoUser = "";
    currentUser = "test-user";
  };
  home = defaults.homeModules.darwin {
    config = { };
    lib = { };
    pkgs = { };
  };
in
{
  testConsolidatedDarwinKeepsSystemAndHomeScopesSeparate = {
    expr = {
      system = host ? system && host ? homebrew;
      homeHasSystemOptions = home ? system || home ? homebrew;
      homeHasAgents = home.launchd ? agents;
      primaryUser = host.system.primaryUser;
    };
    expected = {
      system = true;
      homeHasSystemOptions = false;
      homeHasAgents = true;
      primaryUser = "test-user";
    };
  };
}
