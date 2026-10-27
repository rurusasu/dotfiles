{ inputs }:
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
      modules =
        (import ../../discover-modules.nix "home-manager" ../../modules)
        ++ modules
        ++ [
          {
            home = {
              username = pkgs.lib.mkDefault "test-user";
              homeDirectory = pkgs.lib.mkDefault (
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
  homeModule =
    requested:
    { pkgs, lib, ... }:
    let
      base = (import ../../defaults.nix inputs).systemDefaults {
        inherit inputs pkgs;
        platform = if requested == "common" then "linux" else requested;
      };
    in
    {
      imports =
        if requested == "common" then
          [ (builtins.head base.home-manager.sharedModules) ]
        else
          lib.reverseList base.home-manager.sharedModules;
    };
  mkDarwin =
    modules:
    inputs.nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = {
        inherit inputs;
        platform = "darwin";
      };
      modules =
        (import ../../discover-modules.nix "system" ../../modules)
        ++ (import ../../discover-modules.nix "darwin" ../../modules)
        ++ modules;
    };
  windowsPackages = builtins.listToAttrs (
    builtins.concatMap (
      source:
      builtins.map (package: {
        name = package.PackageIdentifier;
        value = package // {
          source = source.SourceDetails.Name;
        };
      }) source.Packages
    ) (builtins.fromJSON (builtins.readFile ../../../windows/winget/packages.json)).Sources
  );
  pnpmManifest = builtins.fromJSON (builtins.readFile ../../../windows/pnpm/packages.json);
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
      (import ../../defaults.nix inputs).systemDefaults
    ];
  };
}
