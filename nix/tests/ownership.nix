let
  bashTests = ../../tests/bash;
  macosConfig = builtins.readFile (bashTests + "/macos_config.bats");
in
{
  testHomeManagerStructureIsNotOwnedByBats = {
    expr = builtins.map (name: builtins.pathExists (bashTests + "/${name}")) [
      "home_layout.bats"
      "flake_outputs.bats"
    ];
    expected = [
      false
      false
    ];
  };

  testDarwinConfigBatsContainsOnlyRuntimeContracts = {
    expr = builtins.match ".*nix eval.*" macosConfig == null;
    expected = true;
  };
}
