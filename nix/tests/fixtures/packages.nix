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
      sudoUser = "test-user";
      currentUser = "test-user";
    };
    modules = [
      inputs.nix-homebrew.darwinModules.nix-homebrew
      inputs.home-manager.darwinModules.home-manager
      { nixpkgs.pkgs = mkPkgs "aarch64-darwin"; }
      (import ../../default.nix { }).hostModules.darwin
    ];
  };
}
