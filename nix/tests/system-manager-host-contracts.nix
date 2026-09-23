{ inputs }:
let
  system = "x86_64-linux";
  systemManagerModule = import ../flakes/system-manager.nix { inherit inputs; };
  systemConfigs = systemManagerModule.flake.systemConfigs;
  nixos = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = { inherit inputs; };
    modules = [ ../../modules/host/default.nix ];
  };

  supportsDistro =
    distro: config:
    let
      osVersion = config.system-manager.preActivationAssertions.osVersion;
    in
    !config.system-manager.allowAnyDistro
    && osVersion.enable
    && inputs.nixpkgs.lib.hasInfix "if [ $ID = \"${distro}\" ]; then" osVersion.script;

  hostPackages = pkgs:
    (import ../packages/sets.nix {
      inherit pkgs;
      inherit (pkgs) lib;
      codexPackage = inputs."llm-agents".packages.${system}.codex;
    }).hostPackages;

  includesHostPackages =
    config: pkgs:
    builtins.all (
      package: builtins.elem package config.environment.systemPackages
    ) (hostPackages pkgs);

  includesSystemManagerHostPackages = distro:
    let
      config = systemConfigs.${distro}.config;
    in
    includesHostPackages config config.nixpkgs.pkgs;
in
{
  testSystemManagerExposesUbuntuAndDebianConfigs = {
    expr = builtins.hasAttr "ubuntu" systemConfigs && builtins.hasAttr "debian" systemConfigs;
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
