{ inputs, pkgs }:
let
  hermesPackage = inputs.hermes-agent.packages.${pkgs.system}.default;
  # The test home must satisfy the production no-symlink path contract.
  testHermesHome =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "/private/tmp/hermes-test-home"
    else
      "/tmp/hermes-test-home";
  testPython = "${hermesPackage.hermesVenv}/bin/python3";
  bootstrapPython = pkgs.python312.withPackages (pythonPackages: [
    pythonPackages.httpx
    pythonPackages.python-dotenv
    pythonPackages.pyyaml
  ]);
  sourceRoot = ../../..;
  managedWrapper = pkgs.writeShellScriptBin "hermes-profile-sync" (
    builtins.readFile ../../../scripts/sh/hermes-profile-sync.sh
  );
  manifest = pkgs.writeText "hermes-bootstrap-test-manifest.yaml" (
    import ../../home/hermes-agent/manifest.nix { hermesHome = testHermesHome; }
  );
  bootstrapCli = pkgs.writeShellScriptBin "hermes-bootstrap" ''
    export HERMES_HOME=${testHermesHome}
    export HERMES_BOOTSTRAP_MANIFEST=${manifest}
    export PYTHONPATH=${inputs.hermes-agent}:${sourceRoot}/scripts/python
    exec ${bootstrapPython}/bin/python3 ${sourceRoot}/scripts/python/hermes_bootstrap_cli.py "$@"
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
    mkdir -p ${testHermesHome}
    cd ${sourceRoot}
    ${testPython} -m unittest discover \
      -s tests/python/hermes_bootstrap_test \
      -p 'test_*.py' \
      -v
    touch "$out"
  ''
