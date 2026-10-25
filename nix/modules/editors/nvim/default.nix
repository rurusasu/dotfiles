{
  config,
  lib,
  pkgs,
  ...
}:
let
  allocation = import ../../../home/keybindings/bindings.nix { inherit lib; };
in
{
  # プラグインの導入と設定を専用モジュールにまとめる。
  imports = [
    ./plugins.nix
    ./runtime.nix
  ];

  programs.neovim = {
    enable = true;
    # Use the unwrapped package and expose runtime dependencies on the user PATH.
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

  # The former whole-directory Home Manager link must be moved before checking
  # the new per-file Lua layout. Keep the link itself as a recoverable backup.
  home.activation.migrateNeovimLuaDirectoryLink = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    luaDirectory=${lib.escapeShellArg "${config.xdg.configHome}/nvim/lua"}
    if [ -L "$luaDirectory" ]; then
      luaTarget=$(${pkgs.coreutils}/bin/readlink -- "$luaDirectory")
      if [[ "$luaTarget" =~ ^/nix/store/[0-9a-z]{32}-home-manager-files/\.config/nvim/lua$ ]]; then
        luaBackup="$luaDirectory.before-shared-keybindings.$(${pkgs.coreutils}/bin/date +%s).$$"
        if [ -e "$luaBackup" ] || [ -L "$luaBackup" ]; then
          echo "Neovim Lua migration backup already exists: $luaBackup" >&2
          exit 1
        fi
        run ${pkgs.coreutils}/bin/mv --no-target-directory --no-clobber -- "$luaDirectory" "$luaBackup"
      fi
    fi
  '';

  xdg.configFile."nvim/lua" = {
    source = ./lua;
    recursive = true;
  };
  xdg.configFile."nvim/lua/config/shared_keybindings.lua".text =
    lib.optionalString (lib.attrByPath [ "dotfiles" "keybindings" "fromWindowsExport" ] false config) ''
      -- WSL receives exported key data through Windows chezmoi.
      local path = ${builtins.toJSON "${config.xdg.configHome}/dotfiles/keybindings/generated.json"}
      if vim.fn.filereadable(path) == 1 then
          local allocation = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
          return { leader = allocation.neovimLeader, bindings = allocation.neovim }
      end
    ''
    + ''
      -- Bootstrap fallback until the first Windows chezmoi apply.
      return vim.json.decode([==[${
        builtins.toJSON {
          leader = allocation.neovimLeader;
          bindings = allocation.neovim;
        }
      }]==])
    '';
}
