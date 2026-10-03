{ inputs }:
let
  standalone = inputs.self.homeConfigurations.aarch64-darwin;
  renamed = standalone.extendModules {
    modules = [ { home.username = "alice"; } ];
  };
  explicitHome = standalone.extendModules {
    modules = [
      {
        home.username = "alice";
        home.homeDirectory = "/Volumes/Home/alice";
      }
    ];
  };
  identity = home: {
    inherit (home.config.home) username homeDirectory stateVersion;
  };
in
{
  # Removing the standalone default must fail as a value assertion, even when
  # Home Manager throws while forcing its required homeDirectory option.
  testStandaloneDarwinExportHasDefaultIdentity = {
    expr = builtins.tryEval (builtins.deepSeq (identity standalone) (identity standalone));
    expected = {
      success = true;
      value = {
        username = "rurusasu";
        homeDirectory = "/Users/rurusasu";
        stateVersion = "26.05";
      };
    };
  };

  # A hardcoded default directory would keep the old user's home after rename.
  testStandaloneDarwinExportDerivesHomeFromEffectiveUsername = {
    expr = builtins.tryEval (builtins.deepSeq (identity renamed) (identity renamed));
    expected = {
      success = true;
      value = {
        username = "alice";
        homeDirectory = "/Users/alice";
        stateVersion = "26.05";
      };
    };
  };

  # A forced directory would reject an ordinary explicit absolute home.
  testStandaloneDarwinExportAllowsExplicitAbsoluteHome = {
    expr = builtins.tryEval (builtins.deepSeq (identity explicitHome) (identity explicitHome));
    expected = {
      success = true;
      value = {
        username = "alice";
        homeDirectory = "/Volumes/Home/alice";
        stateVersion = "26.05";
      };
    };
  };
}
