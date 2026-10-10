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
      apps =
        lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
          darwin-rebuild.program = lib.getExe inputs.nix-darwin.packages.${system}.darwin-rebuild;
        }
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          home-manager.program = lib.getExe inputs.home-manager.packages.${system}.home-manager;
        };
    };

  mkNixosHostSpecs =
    {
      hardwareConfig ?
        let
          configured = builtins.getEnv "DOTFILES_NIXOS_HARDWARE_CONFIG";
        in
        if configured != "" then
          configured
        else if builtins.pathExists /etc/nixos/hardware-configuration.nix then
          "/etc/nixos/hardware-configuration.nix"
        else
          "",
      requestedSystem ? builtins.currentSystem or "x86_64-linux",
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
      configuredUser ? (import ./shared/nixos/identity.nix { lib = inputs.nixpkgs.lib; }).user,
      homeModulePath ? null,
      extraModules ? [ ],
      overlays ? [ ],
      homeExtraSpecialArgs ? { },
      nativeIdentity ? null,
    }:
    let
      user = selectHomeManagerUser configuredUser;
    in
    inputs.nixpkgs.lib.nixosSystem {
      specialArgs = {
        inherit inputs system nativeIdentity;
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
                }
                // (
                  if nativeIdentity == null then
                    { }
                  else
                    {
                      home.homeDirectory = nativeIdentity.home;
                    }
                );
              };
            }
          ]
        else
          [ ]
      )
      ++ extraModules;
    };
}
