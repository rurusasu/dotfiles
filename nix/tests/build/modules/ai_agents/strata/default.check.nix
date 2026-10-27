{
  inputs,
  pkgs,
  code,
}:
pkgs.lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
  strata-applications = (
    let
      packages = code.nix.modules.ai_agents.strata.package {
        inherit pkgs;
        release = code.nix.modules.ai_agents.strata.release (
          builtins.fromJSON (builtins.readFile inputs.strata-release)
        );
      };
    in
    pkgs.runCommand "strata-applications-check"
      {
        nativeBuildInputs = [ pkgs.desktop-file-utils ];
      }
      ''
        test -x ${packages.control}/bin/strata
        test -x ${packages.desktop}/bin/strata-desktop
        test -x ${packages.control.controlContents}/python/bin/python3
        test "$(cat ${packages.control.controlContents}/VERSION)" = ${pkgs.lib.escapeShellArg packages.control.version}
        desktop-file-validate ${packages.desktop}/share/applications/Strata.desktop
        test -s ${packages.desktop}/share/pixmaps/strata-desktop.png
        touch "$out"
      ''
  );
}
