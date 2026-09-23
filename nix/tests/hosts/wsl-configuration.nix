{ inputs }:
let
  mkWsl =
    withHermes:
    inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        dotfilesWithHermes = withHermes;
      };
      modules = [
        inputs.nixos-wsl.nixosModules.wsl
        ../../hosts/wsl
      ];
    };

  defaultConfig = (mkWsl false).config;
  hermesConfig = (mkWsl true).config;
in
{
  testWslHermesFeatureEnablesUserLinger = {
    expr = hermesConfig.users.users.nixos.linger;
    expected = true;
  };

  testWslUserLingerRemainsDisabledWithoutHermes = {
    expr = defaultConfig.users.users.nixos.linger;
    expected = false;
  };
}
