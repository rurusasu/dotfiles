{ inputs }:
let
  selectHomeManagerUser = configuredUser: if configuredUser == "" then "nixos" else configuredUser;
  linuxHome =
    args@{
      config,
      lib,
      ...
    }:
    let
      currentUser = builtins.getEnv "USER";
      currentHome = builtins.getEnv "HOME";
      # NixOS supplies account identity through Home Manager osConfig.
      hasCurrentUser = !(args ? osConfig) && currentUser != "" && currentUser != "root";
    in
    {
      home = {
        username = lib.mkIf hasCurrentUser currentUser;
        homeDirectory = lib.mkDefault (
          if hasCurrentUser && currentHome != "" then currentHome else "/home/${config.home.username}"
        );
      };

      imports = [
        (import ../modules/tools.nix).linuxDesktop
        (import ../modules/tools.nix).chatgpt
        ../modules/discord
        ../home/common.nix
      ];

      programs.git.signing.signer = "/opt/1Password/op-ssh-sign";
    };
in
{
  inherit selectHomeManagerUser linuxHome;

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
        hostPath = ./wsl.nix;
        homeModule = ../home/wsl.nix;
      };
    }
    // (
      if hardwareConfig == "" then
        { }
      else
        {
          linux = {
            system = if requestedSystem == "" then "x86_64-linux" else requestedSystem;
            hostPath = ./linux.nix;
            homeModule = linuxHome;
            inherit hardwareConfig;
          };
        }
    );

  mkNixos =
    {
      system,
      hostPath,
      configuredUser ? (import ./identity.nix { lib = inputs.nixpkgs.lib; }).user,
      homeModule ? null,
      extraModules ? [ ],
      overlays ? [ ],
      homeExtraSpecialArgs ? { },
      nativeIdentity ? null,
    }:
    inputs.nixpkgs.lib.nixosSystem {
      specialArgs = {
        inherit inputs system nativeIdentity;
      };
      modules = [
        { nixpkgs.hostPlatform = system; }
        hostPath
        { nixpkgs.overlays = overlays; }
      ]
      ++ (
        if homeModule != null then
          [
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = {
                  inherit inputs;
                }
                // homeExtraSpecialArgs;
                users.${selectHomeManagerUser configuredUser} = {
                  imports = [ homeModule ];
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
