# Shared CLI package used by Home Manager and the gateway service.
{
  config,
  inputs,
  lib,
  pkgs,
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
in
pkgs.writeShellApplication {
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
}
