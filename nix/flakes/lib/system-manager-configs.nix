{
  inputs,
  dotfilesUser ? builtins.getEnv "DOTFILES_USER",
  dotfilesHome ? builtins.getEnv "DOTFILES_HOME",
  dotfilesUid ? builtins.getEnv "DOTFILES_UID",
  dotfilesGid ? builtins.getEnv "DOTFILES_GID",
  dotfilesGroup ? builtins.getEnv "DOTFILES_GROUP",
}:
let
  requestedSystem = builtins.getEnv "DOTFILES_SYSTEM";
  system = if requestedSystem == "" then "x86_64-linux" else requestedSystem;
  mkConfig =
    distro:
    inputs.system-manager.lib.makeSystemConfig {
      specialArgs = {
        inherit inputs distro;
        inherit
          dotfilesUser
          dotfilesHome
          dotfilesUid
          dotfilesGid
          dotfilesGroup
          ;
      };
      modules = [
        inputs.home-manager.nixosModules.home-manager
        {
          nixpkgs.hostPlatform = system;
          nixpkgs.config.allowUnfree = true;
        }
        ../../system-manager/default.nix
        ../../system-manager/docker.nix
        ../../system-manager/ollama.nix
      ];
    };
in
{
  ubuntu = mkConfig "ubuntu";
  debian = mkConfig "debian";
}
