{
  pkgs,
  fixtures,
}:
let
  terminalHome = fixtures.mkHome pkgs.stdenv.hostPlatform.system [
    {
      home = {
        username = "test-user";
        homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/test-user" else "/home/test-user";
        stateVersion = "25.05";
      };
      programs.alacritty.enable = true;
    }
  ];
  configFile = terminalHome.config.xdg.configFile."alacritty/alacritty.toml".source;
in
{
  alacritty-config =
    pkgs.runCommand "alacritty-config-check"
      {
        nativeBuildInputs = [ terminalHome.config.programs.alacritty.package ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        alacritty migrate --dry-run --config-file=${configFile} >/dev/null
        touch "$out"
      '';
}
