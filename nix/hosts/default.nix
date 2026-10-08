{ inputs }:
let
  selectHomeManagerUser = configuredUser: if configuredUser == "" then "nixos" else configuredUser;
in
{
  inherit selectHomeManagerUser;

  mkApps =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    {
      apps = lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        darwin-rebuild.program = lib.getExe inputs.nix-darwin.packages.${system}.darwin-rebuild;
      };
    };

  mkNixosHostSpecs =
    {
      hardwareConfig ? builtins.getEnv "DOTFILES_NIXOS_HARDWARE_CONFIG",
      requestedSystem ? builtins.getEnv "DOTFILES_SYSTEM",
    }:
    {
      nixos = {
        system = "x86_64-linux";
        hostPath = ./x86_64-linux/wsl;
        homeModulePath = ./x86_64-linux/wsl/home.nix;
      };
    }
    // (
      if hardwareConfig == "" then
        { }
      else
        {
          linux = rec {
            system = if requestedSystem == "" then "x86_64-linux" else requestedSystem;
            hostPath = ./${system}/nixos;
            homeModulePath = ./${system}/home.nix;
            inherit hardwareConfig;
          };
        }
    );

  mkNixos =
    {
      system,
      hostPath,
      configuredUser ? builtins.getEnv "DOTFILES_USER",
      homeModulePath ? null,
      extraModules ? [ ],
      overlays ? [ ],
      homeExtraSpecialArgs ? { },
    }:
    let
      user = selectHomeManagerUser configuredUser;
    in
    inputs.nixpkgs.lib.nixosSystem {
      specialArgs = {
        inherit inputs system;
      };
      modules = [
        { nixpkgs.hostPlatform = system; }
        hostPath
        { nixpkgs.overlays = overlays; }
        ../hosts/shared/nixos/platform.nix
      ]
      ++ (
        if homeModulePath != null then
          [
            inputs.home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = {
                  inherit inputs;
                }
                // homeExtraSpecialArgs;
                users.${user} = {
                  imports = [ homeModulePath ];
                };
              };
            }
          ]
        else
          [ ]
      )
      ++ extraModules;
    };
}
