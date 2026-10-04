{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Use exactly the home-relative target HM will link, including custom XDG homes.
  nvimDirectory = builtins.dirOf config.xdg.configFile."nvim/lua".target;
  migrateLegacy = pkgs.writeShellScript "migrate-neovim-legacy" ''
    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}:"$PATH"
    ${builtins.readFile ./migrate-legacy.sh}
  '';
  migrationArgs = ''${lib.escapeShellArg nvimDirectory} ${lib.escapeShellArg builtins.storeDir}'';
in
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

  # force は checkLinkTargets を通すためだけに限定する。書き換え前に必ず
  # 全対象を検査・退避し、既存設定をバックアップなしで上書きしない。
  xdg.configFile = {
    "nvim/init.lua".force = true;
    "nvim/lua" = {
      source = ./lua;
      force = true;
    };
  };

  assertions = [
    {
      assertion = config.home.fileActivator == "legacy";
      message = "The Neovim legacy migration requires Home Manager's legacy file activator.";
    }
    {
      assertion =
        config.xdg.configFile."nvim/init.lua".target == "${nvimDirectory}/init.lua"
        && config.xdg.configFile."nvim/lua".target == "${nvimDirectory}/lua";
      message = "Neovim's forced init.lua and lua targets must share the migration directory.";
    }
  ];

  home.activation = {
    checkNeovimLegacyConfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      ${migrateLegacy} check ${migrationArgs} || exit 1
    '';
    migrateNeovimLegacyConfig = lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
      run ${migrateLegacy} apply ${migrationArgs} || exit 1
    '';
  };
}
