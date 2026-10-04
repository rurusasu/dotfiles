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
        ../../../modules/host
        ../../../hosts/wsl
      ];
    };

  defaultConfig = (mkWsl false).config;
  hermesConfig = (mkWsl true).config;
in
{
  testWslInstallsZshBeforeSelectingItAsLoginShell = {
    expr = {
      enabled = defaultConfig.programs.zsh.enable;
      selected = defaultConfig.users.users.nixos.shell == (mkWsl false).pkgs.zsh;
      installed = builtins.elem (mkWsl false).pkgs.zsh defaultConfig.environment.systemPackages;
    };
    expected = {
      enabled = true;
      selected = true;
      installed = true;
    };
  };

  testWslHermesFeatureEnablesUserLinger = {
    expr = hermesConfig.users.users.nixos.linger;
    expected = true;
  };

  testWslUserLingerRemainsDisabledWithoutHermes = {
    expr = defaultConfig.users.users.nixos.linger;
    expected = false;
  };
}
