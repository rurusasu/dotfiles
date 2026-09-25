{ inputs }:
let
  system = "x86_64-linux";
  workmux = import ../flakes/lib/workmux.nix { inherit inputs; };
  workmuxOverlay = workmux.mkOverlay (_: inputs.workmux.packages.${system}.default);

  systemManagerConfig = inputs.system-manager.lib.makeSystemConfig {
    overlays = [ workmuxOverlay ];
    specialArgs = {
      inherit inputs;
      dotfilesUser = "test-user";
      dotfilesHome = "/srv/dotfiles/test-user";
      dotfilesUid = "4242";
      dotfilesGid = "4243";
      dotfilesGroup = "test-primary";
    };
    modules = [
      inputs.home-manager.nixosModules.home-manager
      {
        nixpkgs.hostPlatform = system;
        nixpkgs.config.allowUnfree = true;
      }
      ../system-manager/default.nix
    ];
  };

  config = systemManagerConfig.config;
in
{
  testSystemManagerPreservesRequestedExistingUserIdentity = {
    expr = {
      mutableUsers = config.users.mutableUsers;
      uid = config.users.users.test-user.uid;
      home = config.users.users.test-user.home;
      primaryGroup = config.users.users.test-user.group;
      primaryGroupGid = config.users.groups.test-primary.gid;
      dockerSupplementaryGroup = builtins.elem "docker" config.users.users.test-user.extraGroups;
    };
    expected = {
      mutableUsers = true;
      uid = 4242;
      home = "/srv/dotfiles/test-user";
      primaryGroup = "test-primary";
      primaryGroupGid = 4243;
      dockerSupplementaryGroup = true;
    };
  };
}
