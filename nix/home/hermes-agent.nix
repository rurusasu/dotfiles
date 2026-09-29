{
  config,
  inputs,
  lib,
  pkgs,
  installFeatures ? [ ],
  ...
}:
let
  enabled = builtins.elem "WithHermes" installFeatures;
  hermesHome = "${config.home.homeDirectory}/.hermes";
  bootstrapManifest = pkgs.writeText "hermes-bootstrap-manifest.yaml" (
    import ./hermes-agent/manifest.nix { inherit hermesHome; }
  );
  bootstrapPython = pkgs.python312.withPackages (pythonPackages: [
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
      export PYTHONPATH=${inputs.hermes-agent}:${../../scripts/python}
      exec ${bootstrapPython}/bin/python -m hermes_bootstrap "$@"
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

  programs.hermes-agent.enable = enabled;
  home.sessionVariables.DOTFILES_WITH_HERMES = if enabled then "1" else "0";
  home.packages = lib.optionals enabled [
    hermesBootstrap
    pkgs.nodejs
  ];
  services.hermes-agent = {
    enable = enabled;
    gateway.enable = enabled;
    hermesHome = hermesHome;
    extraPackages = lib.optionals enabled [
      hermesBootstrap
      pkgs.nodejs
    ];
    hermesHomeFiles = lib.optionalAttrs enabled {
      "bootstrap-manifest.yaml" = bootstrapManifest;
      "scripts/profile_sync.sh" = ../../scripts/sh/hermes-profile-sync.sh;
    };
    extraPlugins = lib.optionals enabled [ hermesLcmPlugin ];
    settings.gateway.multiplex_profiles = true;
  };
  home.activation.hermesProfileSyncWrapperExecutable = lib.mkIf enabled (
    lib.hm.dag.entryAfter [ "hermesAgentSetup" ] ''
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod 0700 ${lib.escapeShellArg "${hermesHome}/scripts/profile_sync.sh"}
    ''
  );
}
