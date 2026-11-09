{ pkgs, fixtures }:
let
  home = fixtures.mkHome pkgs.stdenv.hostPlatform.system [ (fixtures.homeModule "common") ];
  settings = (pkgs.formats.toml { }).generate "herdr-config.toml" home.config.programs.herdr.settings;
in
{
  herdr-config =
    pkgs.runCommand "herdr-config-check" { nativeBuildInputs = [ home.config.programs.herdr.package ]; }
      ''
        export HOME="$TMPDIR/home"
        export XDG_CONFIG_HOME="$HOME/.config"
        mkdir -p "$XDG_CONFIG_HOME/herdr"
        cp ${settings} "$XDG_CONFIG_HOME/herdr/config.toml"
        herdr config check
        touch "$out"
      '';
}
