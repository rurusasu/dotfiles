# Shared CLI package used by Home Manager and the gateway service.
{
  config,
  inputs,
  lib,
  pkgs,
}:
let
  hermesHome = "${config.home.homeDirectory}/.hermes";
  bootstrapManifest = pkgs.writeText "hermes-bootstrap-manifest.yaml" (
    import ./manifest.nix { inherit hermesHome; }
  );
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  bundled = pkgs.callPackage ./package.nix { };
  bootstrapPython =
    if isDarwin then
      bundled
    else
      pkgs.python3.withPackages (pythonPackages: [
        pythonPackages.httpx
        pythonPackages.python-dotenv
        pythonPackages.pyyaml
      ]);
in
pkgs.writeShellApplication {
  name = "hermes-bootstrap";
  runtimeInputs = [
    bootstrapPython
    pkgs.git
    pkgs.jq
    pkgs._1password-cli
  ];
  text = ''
    export HERMES_HOME=${lib.escapeShellArg hermesHome}
    export HERMES_BOOTSTRAP_MANIFEST=${bootstrapManifest}
    export DOTFILES_HERMES_GIT_EXECUTABLE=${pkgs.git}/bin/git
    # Select our package even inside the upstream checkout or a conflicting cwd.
    ${
      if isDarwin then
        ''
          unset PYTHONHOME
          export PYTHONPATH=${lib.escapeShellArg "${../../../../scripts/python}:${bundled.hermesSource}:${bundled.sitePackages}"}
          export HERMES_SITE=${lib.escapeShellArg bundled.sitePackages}
          export PYTHONPYCACHEPREFIX="''${PYTHONPYCACHEPREFIX:-''${XDG_CACHE_HOME:-$HOME/.cache}/hermes-pycache}"
          exec ${lib.escapeShellArg bundled.python} -P -c 'import os, runpy, site; site.addsitedir(os.environ["HERMES_SITE"]); runpy.run_module("hermes_bootstrap", run_name="__main__", alter_sys=True)' "$@"
        ''
      else
        ''
          export PYTHONPATH=${../../../../scripts/python}:${inputs.hermes-agent}
          exec ${bootstrapPython}/bin/python -P -m hermes_bootstrap "$@"
        ''
    }
  '';
}
