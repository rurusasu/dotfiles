{ inputs, pkgs }:
let
  activationPackage = inputs.self.homeConfigurations.aarch64-darwin.activationPackage;
in
pkgs.runCommand "standalone-darwin-home-check" { } ''
  test -x ${activationPackage}/activate
  touch "$out"
''
