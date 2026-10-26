{ inputs, pkgs }:
let
  packages = import ../../../../../modules/ai_agents/strata/package.nix {
    inherit pkgs;
    release = import ../../../../../modules/ai_agents/strata/release.nix (
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
