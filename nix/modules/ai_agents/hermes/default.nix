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
  bootstrapPython = pkgs.python3.withPackages (pythonPackages: [
    pythonPackages.httpx
    pythonPackages.python-dotenv
    pythonPackages.pyyaml
  ]);
  hermesBootstrap = pkgs.writeShellApplication {
    name = "hermes-bootstrap";
    runtimeInputs = [
      bootstrapPython
      pkgs.git
      pkgs.jq
      pkgs._1password-cli
    ];
    text = ''
      export HERMES_HOME=${lib.escapeShellArg hermesHome}
      export HERMES_BOOTSTRAP_MANIFEST=${bootstrapManifest}
      export DOTFILES_HERMES_GIT_EXECUTABLE=${pkgs.git}/bin/git
      # Select our package even inside the upstream checkout or a conflicting cwd.
      export PYTHONPATH=${../../../../scripts/python}:${inputs.hermes-agent}
      exec ${bootstrapPython}/bin/python -P -m hermes_bootstrap "$@"
    '';
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

  programs.hermes-agent.enable = true;
  programs.hermes-agent.desktop.enable = true;
  home = {
    packages = [
      hermesBootstrap
      pkgs.nodejs
    ];
    activation.hermesProfileSyncWrapperExecutable = lib.hm.dag.entryAfter [ "hermesAgentSetup" ] ''
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod 0700 ${lib.escapeShellArg "${hermesHome}/scripts/profile_sync.sh"}
    '';
  };
  services.hermes-agent = {
    enable = true;
    gateway.enable = true;
    inherit hermesHome;
    extraPackages = [
      hermesBootstrap
      pkgs.nodejs
    ];
    hermesHomeFiles = {
      "bootstrap-manifest.yaml" = bootstrapManifest;
      "scripts/profile_sync.sh" = ../../../../scripts/sh/hermes-profile-sync.sh;
    };
    extraPlugins = [ hermesLcmPlugin ];
    settings.gateway.multiplex_profiles = true;
  };
}
