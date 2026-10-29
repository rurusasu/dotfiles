{
  pkgs,
  fixtures,
  files,
}:
pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  zsh-patina-disabled-lookups =
    let
      home = fixtures.mkHome pkgs.stdenv.hostPlatform.system [
        {
          programs.zsh.enable = true;
          programs.zsh-patina.enable = true;
        }
      ];
    in
    pkgs.runCommand "zsh-patina-disabled-lookups-check"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.strace
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        python ${files.nix.tests.fixtures.zsh-patina."disabled-lookups.py"} \
          ${pkgs.lib.getExe pkgs.zsh-patina} \
          ${pkgs.lib.getExe home.config.programs.zsh-patina.package}
        touch "$out"
      '';
}
