{ inputs, code }:
let
  registered = (code.nix.defaults inputs).configurations;
  darwin = registered.darwinConfigurations.macos.config;
  wsl = registered.nixosConfigurations.wsl.config;
  settings = config: {
    inherit (config.nix.settings)
      accept-flake-config
      extra-substituters
      extra-trusted-public-keys
      ;
  };
  expected = {
    accept-flake-config = false;
    extra-substituters = [
      "https://cache.numtide.com"
      "https://hermes-agent.cachix.org"
    ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "hermes-agent.cachix.org-1:jN3pjR50Mxi4SESKC/FIMNM6/LCosvPk2VUwzVvebzU="
    ];
  };
in
{
  testNixRejectsFlakeConfigAndUsesDeclaredCaches = {
    expr = {
      darwin = settings darwin;
      wsl = settings wsl;
      linux = settings registered.homeConfigurations.x86_64-linux.config;
      linuxUser = registered.homeConfigurations.x86_64-linux.config.home.username;
      linuxHome = registered.homeConfigurations.x86_64-linux.config.home.homeDirectory;
      integratedUserConfig =
        darwin.home-manager.users.${darwin.system.primaryUser}.xdg.configFile ? "nix/nix.conf";
    };
    expected = {
      darwin = expected;
      wsl = expected;
      linux = expected;
      linuxUser = code.nix.home.settings.username;
      linuxHome = "/home/" + code.nix.home.settings.username;
      integratedUserConfig = false;
    };
  };
}
