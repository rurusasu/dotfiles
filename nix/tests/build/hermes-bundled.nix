{ inputs, pkgs }:
let
  buildPkgs = import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
  package = buildPkgs.callPackage ../../modules/ai_agents/hermes/package.nix { };
  bootstrap = import ../../modules/ai_agents/hermes/bootstrap.nix {
    inherit inputs;
    pkgs = buildPkgs;
    inherit (buildPkgs) lib;
    config.home.homeDirectory = "/var/empty";
  };
in
buildPkgs.runCommand "hermes-bundled-check"
  {
    nativeBuildInputs = [
      package
      bootstrap
    ];
  }
  ''
    export HOME="$TMPDIR/home"
    export HERMES_HOME="$HOME/.hermes"
    mkdir -p "$HOME"
    hermes --version > version.txt
    cat version.txt
    grep -F 'Hermes Agent v${package.version}' version.txt
    grep -F 'Python: 3.14.7' version.txt
    hermes gateway --help > gateway.txt
    grep -F 'run' gateway.txt
    hermes-bootstrap --help > bootstrap.txt
    grep -F 'sync-profiles' bootstrap.txt
    test -x ${package}/bin/hermes-desktop
    test -x ${pkgs.lib.escapeShellArg "${package}/Applications/Hermes Agent.app/Contents/MacOS/Hermes Agent"}
    touch "$out"
  ''
