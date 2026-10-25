# Host registrations and public system / Home Manager configurations.
# Usage:
#   home-manager switch --flake .#aarch64-darwin
#   home-manager switch --flake .#x86_64-linux
#   home-manager switch --flake .#aarch64-linux
{ inputs, ... }:
let
  hosts = import ./. { inherit inputs; };
  garbageCollection = {
    automatic = true;
    options = "--delete-old";
  };
  weeklyGarbageCollection = garbageCollection // {
    dates = "weekly";
  };
  homeGarbageCollection =
    { config, ... }:
    {
      # Integrated homes use the system collector; standalone homes use a user timer.
      nix.gc = weeklyGarbageCollection // {
        automatic = !config.submoduleSupport.enable;
      };
    };
  nativeIdentity = import ./identity.nix { lib = inputs.nixpkgs.lib; };
  mkHome =
    system:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      extraSpecialArgs = { inherit inputs; };
      modules = [
        (if builtins.match ".*-darwin" system != null then ../home/darwin.nix else hosts.linuxHome)
        homeGarbageCollection
      ];
    };
in
{
  homeConfigurations = {
    "aarch64-darwin" = mkHome "aarch64-darwin";
    "x86_64-linux" = mkHome "x86_64-linux";
    "aarch64-linux" = mkHome "aarch64-linux";
  };
  nixosConfigurations = inputs.nixpkgs.lib.mapAttrs (
    _: spec:
    hosts.mkNixos (
      {
        inherit (spec) system hostPath homeModule;
        inherit nativeIdentity;
        extraModules = [
          {
            nix.gc = weeklyGarbageCollection;
            home-manager.sharedModules = [ homeGarbageCollection ];
          }
        ]
        ++ (
          if spec ? hardwareConfig then
            [ (/. + spec.hardwareConfig) ]
          else
            [ inputs.nixos-wsl.nixosModules.wsl ]
        );
      }
      // inputs.nixpkgs.lib.optionalAttrs (nativeIdentity != null) {
        configuredUser = nativeIdentity.user;
      }
    )
  ) (hosts.mkNixosHostSpecs { });
  darwinConfigurations.macos = inputs.nix-darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    specialArgs = {
      inherit inputs;
      sudoUser = builtins.getEnv "SUDO_USER";
      currentUser = builtins.getEnv "USER";
    };
    modules = [
      inputs.nix-homebrew.darwinModules.nix-homebrew
      inputs.home-manager.darwinModules.home-manager
      {
        nixpkgs.config.allowUnfree = true;
        nix.gc = garbageCollection // {
          interval = [
            {
              Weekday = 7;
              Hour = 3;
              Minute = 15;
            }
          ];
        };
        # Collect unreferenced paths during builds when free space falls below 10 GiB.
        nix.settings.min-free = 10 * 1024 * 1024 * 1024;
        home-manager.sharedModules = [ homeGarbageCollection ];
      }
      ./darwin.nix
    ];
  };
}
