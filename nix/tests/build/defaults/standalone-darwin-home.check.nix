{ inputs, pkgs }:
pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
  standalone-darwin-home = (
    pkgs.runCommand "standalone-darwin-home-check" { } ''
      test -x ${inputs.self.homeConfigurations.aarch64-darwin.activationPackage}/activate
      touch "$out"
    ''
  );
}
