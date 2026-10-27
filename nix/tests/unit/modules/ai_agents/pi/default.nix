{
  inputs,
  homeConfigurations ? import ../../../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations)
    darwin
    wsl
    linux
    mkHome
    ;
  disabled = mkHome {
    system = "x86_64-linux";
    module = { lib, ... }: {
      imports = [ ((import ../../../../fixtures/packages.nix { inherit inputs; }).homeModule "wsl") ];
      programs.pi-coding-agent.enable = lib.mkForce false;
    };
  };
  piState = home: {
    enabled = home.config.programs.pi-coding-agent.enable;
    installed = builtins.any (
      package: package.drvPath == home.config.programs.pi-coding-agent.package.drvPath
    ) home.config.home.packages;
    hasManagedSettings = home.config.programs.pi-coding-agent.settings != { };
    hasManagedModels = home.config.programs.pi-coding-agent.models != { };
  };
in
{
  testPiEnabledOnlyOnDarwinAndWsl = {
    expr = map piState [
      darwin
      wsl
      linux
    ];
    expected = [
      {
        enabled = true;
        installed = true;
        hasManagedSettings = true;
        hasManagedModels = true;
      }
      {
        enabled = true;
        installed = true;
        hasManagedSettings = true;
        hasManagedModels = true;
      }
      {
        enabled = false;
        installed = false;
        hasManagedSettings = false;
        hasManagedModels = false;
      }
    ];
  };
  testPiModuleCanBeImportedWithoutEnablingPi = {
    expr = piState disabled;
    expected = {
      enabled = false;
      installed = false;
      hasManagedSettings = false;
      hasManagedModels = false;
    };
  };
}
