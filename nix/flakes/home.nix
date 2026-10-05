# Standalone Home Manager configurations for non-NixOS systems.
# Usage:
#   home-manager switch --flake .#aarch64-darwin
#   home-manager switch --flake .#x86_64-linux
#   home-manager switch --flake .#aarch64-linux
# Hermes Desktop is a Homebrew Cask and therefore requires the nix-darwin
# installer instead of this standalone Home Manager output.
{ inputs, ... }:
let
  withHermes = builtins.getEnv "DOTFILES_WITH_HERMES" == "1";
  withDocker = builtins.getEnv "DOTFILES_WITH_DOCKER" == "1";
  installFeatures = import ./lib/install-features.nix {
    inherit withDocker withHermes;
    inherit (inputs.nixpkgs) lib;
    withOllama = builtins.getEnv "DOTFILES_WITH_OLLAMA" == "1";
  };
  mkHome = system: {
    pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    extraSpecialArgs = {
      inherit inputs installFeatures;
    };
  };
  mkDarwinHome =
    system:
    if withHermes then
      throw "Hermes Desktop requires the nix-darwin installer; run ./install.sh --with-hermes"
    else
      inputs.home-manager.lib.homeManagerConfiguration {
        inherit (mkHome system) pkgs extraSpecialArgs;
        modules = [
          ../home/darwin.nix
          ../modules/shells/zsh
          ../modules/lsp.nix
          ../modules/terminals/ghostty/defaults.nix
          ../modules/darwin/ghostty.nix
          ../modules/terminals/wezterm/defaults.nix
          ../modules/darwin/wezterm.nix
        ];
      };
  mkLinuxHome =
    system:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit (mkHome system) pkgs extraSpecialArgs;
      modules = [
        ../home/linux.nix
        ../modules/shells/zsh
        ../modules/lsp.nix
        ../modules/terminals/ghostty/defaults.nix
        ../modules/nixos/ghostty.nix
        ../modules/terminals/wezterm/defaults.nix
      ];
    };
in
{
  flake.homeConfigurations = {
    "aarch64-darwin" = mkDarwinHome "aarch64-darwin";
    "x86_64-linux" = mkLinuxHome "x86_64-linux";
    "aarch64-linux" = mkLinuxHome "aarch64-linux";
  };
}
