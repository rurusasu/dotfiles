{ inputs, pkgs }:
let
  bootstrapPython = pkgs.python3.withPackages (pythonPackages: [
    pythonPackages.httpx
    pythonPackages.python-dotenv
    pythonPackages.pyyaml
  ]);
  # Test the bootstrap's real dependency environment, not Hermes' optional
  # audio/ML stack. The pinned upstream source still supplies its actual APIs.
  testPython = "${bootstrapPython}/bin/python3";
  sourceRoot = ../../..;
  managedWrapper = pkgs.writeShellScriptBin "hermes-profile-sync" (
    builtins.readFile ../../../scripts/sh/hermes-profile-sync.sh
  );
  manifestTemplate = pkgs.writeText "hermes-bootstrap-test-manifest-template.yaml" (
    import ../../modules/hermes-agent/manifest.nix {
      hermesHome = "/__hermes_bootstrap_test_home__";
    }
  );
  bootstrapCli = pkgs.writeShellScriptBin "hermes-bootstrap" ''
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
    export DOTFILES_HERMES_MANAGED_WRAPPER="${managedWrapper}/bin/hermes-profile-sync"
    export DOTFILES_HERMES_GIT_EXECUTABLE="${pkgs.git}/bin/git"
    cd ${sourceRoot}
    # The launcher bakes a fresh canonical home and matching SSOT manifest,
    # surviving the wrapper contract's deliberately minimal child environment.
    ${testPython} tests/python/hermes_bootstrap_test/build_fixture.py \
      --manifest-template ${manifestTemplate} \
      --bootstrap-cli ${bootstrapCli}/bin/hermes-bootstrap \
      --temporary-root "$TMPDIR" \
      --shell ${pkgs.runtimeShell} \
      -- ${testPython} -m unittest discover \
      -s tests/python/hermes_bootstrap_test \
      -p 'test_*.py' \
      -v
    touch "$out"
  ''
