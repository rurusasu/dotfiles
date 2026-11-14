{
  pkgs,
  fixtures,
  files,
}:
let
  home = fixtures.mkHome pkgs.stdenv.hostPlatform.system [
    { programs.zsh.enable = true; }
  ];
  init = pkgs.writeText "rfg-zsh-init" home.config.programs.zsh.initContent;
in
{
  ripgrep-editor-boundary =
    pkgs.runCommand "ripgrep-editor-boundary-check"
      {
        nativeBuildInputs = [
          pkgs.zsh
          pkgs.ripgrep
          pkgs.fzf
          pkgs.vim
        ];
      }
      ''
        ${pkgs.python3}/bin/python3 ${files.nix.tests.build.modules.shells.plugins.ripgrep."runtime.py"} \
          ${init} ${pkgs.lib.getExe pkgs.zsh} ${pkgs.lib.getExe pkgs.vim}
        touch "$out"
      '';
}
