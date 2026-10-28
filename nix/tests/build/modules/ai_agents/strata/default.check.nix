{
  inputs,
  pkgs,
  code,
}:
pkgs.lib.optionalAttrs
  (builtins.elem pkgs.stdenv.hostPlatform.system [
    "x86_64-linux"
    "aarch64-darwin"
  ])
  {
    strata-applications =
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
          nativeBuildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.desktop-file-utils ];
        }
        ''
          test -x ${packages.control}/bin/strata
          test -x ${packages.desktop}/bin/strata-desktop
          test -x ${packages.control.controlContents}/python/bin/python3
          test "$(cat ${packages.control.controlContents}/VERSION)" = ${pkgs.lib.escapeShellArg packages.control.version}
          ${
            if pkgs.stdenv.hostPlatform.isDarwin then
              ''
                /usr/bin/codesign --verify --deep --strict ${packages.desktop}/Applications/Strata.app
                test -x ${packages.desktop}/Applications/Strata.app/Contents/Resources/control/python/bin/python3
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME"
                ${packages.control}/bin/strata --version | grep -F ${pkgs.lib.escapeShellArg packages.control.productVersion}
              ''
            else
              ''
                desktop-file-validate ${packages.desktop}/share/applications/Strata.desktop
                test -s ${packages.desktop}/share/pixmaps/strata-desktop.png
                # Resolve the actual GUI's libraries without requiring a display
                # or nested bubblewrap namespaces in the build sandbox.
                ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 \
                  --library-path ${packages.desktop.desktopContents}/usr/lib:${packages.desktop.fhsenv}/usr/lib64 \
                  --list ${packages.desktop.desktopContents}/usr/bin/strata-desktop
              ''
          }
          touch "$out"
        '';
  }
