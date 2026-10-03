{
  config,
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
    # Home Manager で Neovim のパッケージを導入する。
    enable = true;
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

  # lazygit など、Neovim の外から呼ぶ補助コマンドもここで導入する。
  home.packages = [
    pkgs.neovim-remote
  ]
  ++ (pkgs.neovimUtils.makeVimPackageInfo (
    map (
      plugin: if plugin ? plugin then builtins.removeAttrs plugin [ "runtime" ] else plugin
    ) config.programs.neovim.plugins
  )).runtimeDeps;

  # 補助 Lua も Home Manager が配置する。
  xdg.configFile."nvim/lua".source = ./lua;
}
