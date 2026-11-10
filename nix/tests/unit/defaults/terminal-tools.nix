{ fixtures, inputs }:
let
  systems = [
    "aarch64-darwin"
    "x86_64-linux"
    "aarch64-linux"
  ];
in
{
  testTerminalToolsUseNativeHomeManagerModules = {
    expr = map (
      system:
      let
        home = fixtures.mkHome system [ (fixtures.homeModule "common") ];
        cfg = home.config;
      in
      {
        inherit system;
        herdr = cfg.programs.herdr.enable;
        herdrPackage = cfg.programs.herdr.package.drvPath;
        herdrConfig = {
          mutable = cfg.programs.herdr.mutableSettings;
          mergeActivation = cfg.home.activation ? herdrMutableSettings;
          immutableFile = cfg.xdg.configFile ? "herdr/config.toml";
        };
      }
    ) systems;
    expected = map (system: {
      inherit system;
      herdr = true;
      herdrPackage = inputs.herdr.packages.${system}.default.drvPath;
      herdrConfig = {
        mutable = true;
        mergeActivation = true;
        immutableFile = false;
      };
    }) systems;
  };
}
