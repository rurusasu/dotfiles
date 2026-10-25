{ inputs, pkgs }:
pkgs.runCommand "standalone-darwin-home-check" { } ''
  test -x ${inputs.self.homeConfigurations.aarch64-darwin.activationPackage}/activate
  touch "$out"
''
