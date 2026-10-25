{ inputs }:
let
  mkPkgs =
    system:
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
in
{
  inherit mkPkgs;
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
  mkHome =
    system: modules:
    let
      pkgs = mkPkgs system;
    in
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit inputs; };
      modules = modules ++ [
        {
          home = {
            username = "test-user";
            homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/test-user" else "/home/test-user";
            stateVersion = "25.05";
          };
        }
      ];
    };
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
