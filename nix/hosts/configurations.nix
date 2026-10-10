# Host registrations and public system / Home Manager configurations.
# Usage:
#   home-manager switch --flake .#aarch64-darwin
#   home-manager switch --flake .#x86_64-linux
#   home-manager switch --flake .#aarch64-linux
{ inputs, ... }:
let
  hosts = import ./. { inherit inputs; };
  hostSpecs = hosts.mkNixosHostSpecs { };
  mkHome = system: {
    pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    extraSpecialArgs = {
      inherit inputs;
    };
  };
  mkDarwinHome =
    system:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit (mkHome system) pkgs extraSpecialArgs;
      modules = [
        ./aarch64-darwin/home.nix
        ../modules/shells/zsh
        ../modules/lsp.nix
        ../modules/terminals/ghostty/defaults.nix
        ../hosts/aarch64-darwin/ghostty.nix
        ../modules/terminals/wezterm/defaults.nix
        ../hosts/aarch64-darwin/wezterm.nix
      ];
    };
  mkLinuxHome =
    system:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit (mkHome system) pkgs extraSpecialArgs;
      modules = [
        ./${system}/home.nix
        ../modules/shells/zsh
        ../modules/lsp.nix
        ../modules/terminals/ghostty/defaults.nix
        ../hosts/shared/linux-ghostty.nix
        ../modules/terminals/wezterm/defaults.nix
      ];
    };
in
{
  homeConfigurations = {
    "aarch64-darwin" = mkDarwinHome "aarch64-darwin";
    "x86_64-linux" = mkLinuxHome "x86_64-linux";
    "aarch64-linux" = mkLinuxHome "aarch64-linux";
  };
  nixosConfigurations = inputs.nixpkgs.lib.mapAttrs (
    _: spec:
    let
      nativeIdentity = import ./shared/nixos/identity.nix { lib = inputs.nixpkgs.lib; };
    in
    hosts.mkNixos (
      {
        inherit (spec) system hostPath homeModulePath;
        inherit nativeIdentity;
        extraModules =
          if spec ? hardwareConfig then
            [ (/. + spec.hardwareConfig) ]
          else
            [ inputs.nixos-wsl.nixosModules.wsl ];
      }
      // inputs.nixpkgs.lib.optionalAttrs (nativeIdentity != null) {
        configuredUser = nativeIdentity.user;
      }
    )
  ) hostSpecs;
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
      { nixpkgs.config.allowUnfree = true; }
      ./aarch64-darwin
    ];
  };
}
