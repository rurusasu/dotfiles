{ inputs }:
let
  system = "x86_64-linux";
  systemManagerModule = import ../flakes/system-manager.nix { inherit inputs; };
  systemConfigs = import ../flakes/lib/system-manager-configs.nix {
    inherit inputs;
    dotfilesUser = "test-user";
    dotfilesHome = "/srv/dotfiles/test-user";
    dotfilesUid = "4242";
    dotfilesGid = "4243";
    dotfilesGroup = "test-primary";
  };
  moduleSystemConfigs = systemManagerModule.flake.systemConfigs;
  workmux = import ../flakes/lib/workmux.nix { inherit inputs; };
  workmuxOverlay = workmux.mkOverlay (target: inputs.workmux.packages.${target}.default);
  nixos = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = { inherit inputs; };
    modules = [
      { nixpkgs.overlays = [ workmuxOverlay ]; }
      ../modules/host/default.nix
    ];
  };

  supportsDistro =
    distro: config:
    let
      osVersion = config.system-manager.preActivationAssertions.osVersion;
    in
    !config.system-manager.allowAnyDistro
    && osVersion.enable
    && inputs.nixpkgs.lib.hasInfix "if [ $ID = \"${distro}\" ]; then" osVersion.script;

  hostPackages =
    pkgs:
    (import ../packages/sets.nix {
      inherit pkgs;
      inherit (pkgs) lib;
      codexPackage = inputs."llm-agents".packages.${system}.codex;
    }).hostPackages;

  includesHostPackages =
    config: pkgs:
    builtins.all (package: builtins.elem package config.environment.systemPackages) (hostPackages pkgs);

  includesSystemManagerHostPackages =
    distro:
    let
      config = systemConfigs.${distro}.config;
    in
    includesHostPackages config config.nixpkgs.pkgs;
in
{
  testSystemManagerExposesUbuntuAndDebianConfigs = {
    expr =
      builtins.hasAttr "ubuntu" moduleSystemConfigs && builtins.hasAttr "debian" moduleSystemConfigs;
    expected = true;
  };

  testSystemManagerConfigsKeepUbuntuAndDebianInSupportedDistroGuard = {
    expr = {
      ubuntu = supportsDistro "ubuntu" systemConfigs.ubuntu.config;
      debian = supportsDistro "debian" systemConfigs.debian.config;
    };
    expected = {
      ubuntu = true;
      debian = true;
    };
  };

  testSystemManagerForwardsUserIdentityThroughSpecialArgs = {
    expr = {
      uid = systemConfigs.ubuntu.config.users.users.test-user.uid;
      home = systemConfigs.ubuntu.config.users.users.test-user.home;
      primaryGroup = systemConfigs.ubuntu.config.users.users.test-user.group;
      primaryGroupGid = systemConfigs.ubuntu.config.users.groups.test-primary.gid;
    };
    expected = {
      uid = 4242;
      home = "/srv/dotfiles/test-user";
      primaryGroup = "test-primary";
      primaryGroupGid = 4243;
    };
  };

  testSystemManagerDoesNotUseDeprecatedExtraSpecialArgs = {
    expr = builtins.any (
      warning: inputs.nixpkgs.lib.hasInfix "extraSpecialArgs is deprecated" warning
    ) systemConfigs.ubuntu.config.warnings;
    expected = false;
  };

  testSystemManagerInputFollowsRootNixpkgsLockNode = {
    expr =
      let
        nodes = (builtins.fromJSON (builtins.readFile ../../flake.lock)).nodes;
      in
      nodes ? nixpkgs
      && builtins.hasAttr "system-manager" nodes
      && (nodes."system-manager".inputs.nixpkgs or null) == [ "nixpkgs" ];
    expected = true;
  };

  testHermesAgentInputIsPinnedToReviewedRevision = {
    expr =
      let
        lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
        hermesInput = lock.nodes.${lock.nodes.${lock.root}.inputs."hermes-agent"};
      in
      hermesInput.locked.rev;
    expected = "d337b736aa1e8ebecfab043842d13e4a2d2f48a3";
  };

  testSystemManagerInstallsGitHubCliAtSystemLevel = {
    expr = {
      ubuntu = includesSystemManagerHostPackages "ubuntu";
      debian = includesSystemManagerHostPackages "debian";
    };
    expected = {
      ubuntu = true;
      debian = true;
    };
  };

  testNixOSInstallsGitHubCliAtSystemLevel = {
    expr = includesHostPackages nixos.config nixos.pkgs;
    expected = true;
  };
}
