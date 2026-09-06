{ inputs, ... }:
let
  system = "aarch64-darwin";
  Workmux = import ./lib/workmux.nix { inherit inputs; };
  workmuxOverlay = Workmux.mkOverlay (_: inputs.workmux.packages.${system}.default);
in
{
  flake.darwinConfigurations.macos = inputs.nix-darwin.lib.darwinSystem {
    inherit system;
    specialArgs = {
      inherit inputs;
      dotfilesUser = builtins.getEnv "DOTFILES_USER";
      dotfilesHome = builtins.getEnv "DOTFILES_HOME";
      dotfilesWithHermes = builtins.getEnv "DOTFILES_WITH_HERMES" == "1";
      dotfilesWithDocker = builtins.getEnv "DOTFILES_WITH_DOCKER" == "1";
      dotfilesWithOllama = builtins.getEnv "DOTFILES_WITH_OLLAMA" == "1";
    };
    modules = [
      inputs.nix-homebrew.darwinModules.nix-homebrew
      inputs.home-manager.darwinModules.home-manager
      {
        nixpkgs.config.allowUnfree = true;
        nixpkgs.overlays = [ workmuxOverlay ];
      }
      ../hosts/darwin
    ];
  };
}
