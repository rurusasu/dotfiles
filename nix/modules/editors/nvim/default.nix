{
  lib,
  pkgs,
  ...
}:
{
  # プラグインの導入と設定を専用モジュールにまとめる。
  imports = [
    ./plugins.nix
  ];

  programs.neovim = {
    # Use the unwrapped package; tools.nix owns CLI enablement.
    package = pkgs.neovim-unwrapped;
    # プラグインの実行依存も内部 PATH ではなく通常のユーザー環境へ導入する。
    autowrapRuntimeDeps = false;
    # Python 製プラグイン用の外部ホストを無効にする。
    withPython3 = false;
    # Ruby 製プラグイン用の外部ホストを無効にする。
    withRuby = false;
    # Home Manager が init.lua を生成し、プラグイン設定より先に基本設定を読む。
    initLua = lib.mkBefore (builtins.readFile ./init.lua);
  };

  xdg.configFile."nvim/lua".source = ./lua;
}
