# Standalone Home Manager configurations for non-NixOS systems.
# Usage:
#   home-manager switch --flake .#aarch64-darwin
#   home-manager switch --flake .#x86_64-linux
#   home-manager switch --flake .#aarch64-linux
{ inputs, ... }:
let
  withHermes = builtins.getEnv "DOTFILES_WITH_HERMES" == "1";
  withDocker = withHermes || builtins.getEnv "DOTFILES_WITH_DOCKER" == "1";
  withOllama = withDocker || builtins.getEnv "DOTFILES_WITH_OLLAMA" == "1";
  installFeatures =
    inputs.nixpkgs.lib.optionals withOllama [ "WithOllama" ]
    ++ inputs.nixpkgs.lib.optionals withDocker [ "WithDocker" ]
    ++ inputs.nixpkgs.lib.optionals withHermes [ "WithHermes" ];
  Workmux = import ./lib/workmux.nix { inherit inputs; };
  workmuxOverlay = Workmux.mkOverlay (system: inputs.workmux.packages.${system}.default);
  mkHome = system: {
    pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [ workmuxOverlay ];
    };
    extraSpecialArgs = {
      inherit inputs installFeatures;
      isWSL = false;
    };
  };
  mkDarwinHome =
    system:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit (mkHome system) pkgs extraSpecialArgs;
      modules = [ ../home/darwin.nix ];
    };
  mkLinuxHome =
    system:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit (mkHome system) pkgs extraSpecialArgs;
      modules = [ ../home/linux.nix ];
    };
in
{
  flake.homeConfigurations = {
    "aarch64-darwin" = mkDarwinHome "aarch64-darwin";
    "x86_64-linux" = mkLinuxHome "x86_64-linux";
    "aarch64-linux" = mkLinuxHome "aarch64-linux";
  };
}
