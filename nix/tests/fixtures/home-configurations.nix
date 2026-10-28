{
  inputs,
  fixtures,
  code,
}:
let
  inherit (fixtures) mkPkgs;

  testHome = {
    username = "test-user";
    homeDirectory = "/home/test-user";
    stateVersion = "25.05";
  };

  mkHome =
    {
      system,
      module,
      specialArgs ? { },
    }:
    fixtures.mkHomeWith {
      inherit system;
      extraSpecialArgs = specialArgs;
      modules = [
        (_: { home = testHome; })
        module
      ];
    };

  linux = mkHome {
    system = "x86_64-linux";
    module = fixtures.homeModule "linux";
  };

  wsl = mkHome {
    system = "x86_64-linux";
    module = fixtures.homeModule "wsl";
  };

  darwin = mkHome {
    system = "aarch64-darwin";
    module = fixtures.homeModule "darwin";
  };

in
{
  inherit
    mkHome
    mkPkgs
    testHome
    linux
    wsl
    darwin
    ;
  linuxArm = mkHome {
    system = "aarch64-linux";
    module = fixtures.homeModule "linux";
  };
  configuredChrome = home: code.nix.modules.browsers.chrome.package { inherit (home) pkgs; };
  common = mkHome {
    system = "x86_64-linux";
    module = fixtures.homeModule "common";
  };
  homes = [
    linux
    wsl
    darwin
  ];
  lib = inputs.nixpkgs.lib;
}
