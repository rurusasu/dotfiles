{ inputs, pkgs }:
let
  hermesPackage = inputs.hermes-agent.packages.${pkgs.system}.default;
  python = "${hermesPackage.hermesVenv}/bin/python3";
  sourceRoot = ../../..;
  managedWrapper = pkgs.writeShellScriptBin "hermes-profile-sync" (
    builtins.readFile ../../../scripts/sh/hermes-profile-sync.sh
  );
  manifest = pkgs.writeText "hermes-bootstrap-test-manifest.yaml" (
    import ../../home/hermes-agent/manifest.nix { hermesHome = "/tmp/hermes-test-home"; }
  );
  bootstrapCli = pkgs.writeShellScriptBin "hermes-bootstrap" ''
    export HERMES_HOME=/tmp/hermes-test-home
    export HERMES_BOOTSTRAP_MANIFEST=${manifest}
    export PYTHONPATH=${inputs.hermes-agent}:${sourceRoot}/scripts/python
    exec ${python} -m hermes_bootstrap "$@"
  '';
in
pkgs.runCommand "hermes-bootstrap-tests"
  {
    nativeBuildInputs = [ pkgs.git ];
  }
  ''
    export PYTHONPATH="${inputs.hermes-agent}:${sourceRoot}/scripts/python"
    export DOTFILES_HERMES_BOOTSTRAP_EXECUTABLE="${bootstrapCli}/bin/hermes-bootstrap"
    export DOTFILES_HERMES_MANAGED_WRAPPER="${managedWrapper}/bin/hermes-profile-sync"
    export DOTFILES_HERMES_GIT_EXECUTABLE="${pkgs.git}/bin/git"
    export PATH="${bootstrapCli}/bin:$PATH"
    cd ${sourceRoot}
    ${python} -m unittest discover \
      -s tests/python/hermes_bootstrap_test \
      -p 'test_*.py' \
      -v
    touch "$out"
  ''
