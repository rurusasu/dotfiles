{ lib, ... }:
{
  # プラグインの導入と設定を専用モジュールにまとめる。
  imports = [ ./plugins.nix ];

  programs.neovim = {
    # Home Manager で Neovim のパッケージを導入する。
    enable = true;
    # Python 製プラグイン用の外部ホストを無効にする。
    withPython3 = false;
    # Ruby 製プラグイン用の外部ホストを無効にする。
    withRuby = false;
    # Home Manager が init.lua を生成し、プラグイン設定より先に基本設定を読む。
    initLua = lib.mkBefore (builtins.readFile ./init.lua);
  };

  # 補助 Lua も Home Manager が配置する。
  xdg.configFile."nvim/lua".source = ./lua;
}
