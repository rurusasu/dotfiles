{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
{
  testDshUsesNixpkgsAcrossLinuxHomes = {
    expr =
      map
        (home: {
          nixpkgsPackage = builtins.elem home.pkgs.deepseek-harness home.config.home.packages;
          externalPackage =
            builtins.elem inputs.llm-agents.packages.${home.pkgs.stdenv.hostPlatform.system}.dsh
              home.config.home.packages;
        })
        [
          homeConfigurations.linux
          homeConfigurations.wsl
          (homeConfigurations.mkHome {
            system = "aarch64-linux";
            module = (import ../../fixtures/packages.nix { inherit inputs; }).homeModule "linux";
          })
        ];
    expected = [
      {
        nixpkgsPackage = true;
        externalPackage = false;
      }
      {
        nixpkgsPackage = true;
        externalPackage = false;
      }
      {
        nixpkgsPackage = true;
        externalPackage = false;
      }
    ];
  };

  testDshRetainsExternalPackageOnDarwin = {
    expr = builtins.elem inputs.llm-agents.packages.aarch64-darwin.dsh homeConfigurations.darwin.config.home.packages;
    expected = true;
  };
}
