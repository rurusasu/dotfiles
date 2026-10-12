{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  hermesHome = "${config.home.homeDirectory}/.hermes";
  bootstrapManifest = pkgs.writeText "hermes-bootstrap-manifest.yaml" (
    import ./manifest.nix { inherit hermesHome; }
  );
  hermesBootstrap = import ./bootstrap.nix {
    inherit
      config
      inputs
      lib
      pkgs
      ;
  };
  hermesLcmPlugin = pkgs.fetchFromGitHub {
    name = "hermes-lcm";
    owner = "stephenschoettler";
    repo = "hermes-lcm";
    rev = "49e99a272d2d461e5c90732e7ef2bc20e96f0826";
    hash = "sha256-yJ1Nn+su7YbKd+cgVOizXChzLbKHqTprSprF1p9/HYk=";
  };
in
{
  imports = [ inputs.hermes-agent.homeManagerModules.default ];

  home = {
    activation.hermesProfileSyncWrapperExecutable = lib.hm.dag.entryAfter [ "hermesAgentSetup" ] ''
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod 0700 ${lib.escapeShellArg "${hermesHome}/scripts/profile_sync.sh"}
    '';
  };
  services.hermes-agent = {
    enable = true;
    gateway.enable = true;
    inherit hermesHome;
    extraPackages = [ hermesBootstrap ];
    hermesHomeFiles = {
      "bootstrap-manifest.yaml" = bootstrapManifest;
      "scripts/profile_sync.sh" = ../../../../scripts/sh/hermes-profile-sync.sh;
    };
    extraPlugins = [ hermesLcmPlugin ];
    settings.gateway.multiplex_profiles = true;
  };
}
