{
  inputs,
  code,
}:
let
  mkPkgs =
    system:
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
  mkHomeWith =
    {
      system,
      modules,
      extraSpecialArgs ? { },
    }:
    let
      pkgs = mkPkgs system;
    in
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs;
      }
      // extraSpecialArgs;
      modules = [
        code.nix.modules.default
        ({ lib, ... }: {
          _module.args.platform = lib.mkDefault (
            if pkgs.stdenv.hostPlatform.isDarwin then "darwin" else "linux"
          );
        })
      ]
      ++ modules
      ++ [
        # The common composition supplies the flake wrapper's package defaults.
        # Import only the base options here to avoid defining those defaults twice.
        (inputs.catppuccin + "/modules/home-manager")
        {
          home = {
            username = pkgs.lib.mkOverride 900 "test-user";
            homeDirectory = pkgs.lib.mkOverride 900 (
              if pkgs.stdenv.hostPlatform.isDarwin then "/Users/test-user" else "/home/test-user"
            );
            stateVersion = pkgs.lib.mkOverride 900 "25.05";
          };
        }
      ];
    };
in
{
  inherit mkPkgs mkHomeWith;
  homeModule = requested: { pkgs, lib, ... }: {
    imports = [ code.nix.home.default ];
    _module.args.platform = lib.mkForce (
      if requested == "common" then
        (if pkgs.stdenv.hostPlatform.isDarwin then "darwin" else "linux")
      else
        requested
    );
  };
  mkDarwin =
    modules:
    inputs.nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = {
        inherit inputs;
        platform = "darwin";
      };
      modules = [ code.nix.modules.fonts.darwin ] ++ modules;
    };
  mkHome = system: modules: mkHomeWith { inherit system modules; };
  darwin = inputs.nix-darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    specialArgs = {
      inherit inputs;
      platform = "darwin";
    };
    modules = [
      {
        nixpkgs.pkgs = mkPkgs "aarch64-darwin";
        system.primaryUser = "test-user";
      }
      code.nix.hosts.default
    ];
  };
}
