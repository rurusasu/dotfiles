{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.programs.neovim.enable {
    programs.neovim.plugins = [
      # 構文解析に使う言語を指定し、Tree-sitter を標準オプションで導入する。
      (pkgs.vimPlugins.nvim-treesitter.withPlugins (
        grammars: with grammars; [
          bash
          c
          css
          go
          html
          javascript
          jsdoc
          json
          lua
          markdown
          markdown_inline
          nix
          python
          query
          regex
          rust
          toml
          tsx
          typescript
          vim
          vimdoc
          yaml
        ]
      ))
      # ファイル一覧と Markdown 表示で使うアイコンを導入する。
      pkgs.vimPlugins.nvim-web-devicons
      # ディレクトリをバッファとして編集し、分割表示と隠しファイルに対応する。
      {
        plugin = pkgs.vimPlugins.oil-nvim;
        type = "lua";
        config = ''require("plugins.oil")'';
      }
      # Git の変更箇所を行番号横に表示する。
      {
        plugin = pkgs.vimPlugins.gitsigns-nvim;
        type = "lua";
        config = ''require("plugins.gitsigns")'';
      }
      # 編集モードに応じてカーソル行の色を変える。
      {
        # nixpkgs にないプラグインのソースは flake.lock で固定する。
        plugin = pkgs.vimUtils.buildVimPlugin {
          name = "modes.nvim";
          src = inputs.modes-nvim;
        };
        type = "lua";
        config = ''require("plugins.modes")'';
      }
      # キー操作の候補を表示する。
      {
        plugin = pkgs.vimPlugins.which-key-nvim;
        type = "lua";
        config = ''require("plugins.which_key")'';
      }
      # 括弧を補完し、Enter は標準補完のキー設定に任せる。
      {
        plugin = pkgs.vimPlugins.nvim-autopairs;
        type = "lua";
        config = ''require("plugins.autopairs")'';
      }
      # 括弧や引用符の追加・変更・削除を行う。
      {
        plugin = pkgs.vimPlugins.nvim-surround;
        type = "lua";
        config = ''require("plugins.surround")'';
      }
      # インデントの深さをガイド線で表示する。
      {
        plugin = pkgs.vimPlugins.indent-blankline-nvim;
        type = "lua";
        config = ''require("plugins.indent_blankline")'';
      }
      # 挿入・ターミナルモードで jk を押すと通常モードに戻る。
      {
        plugin = pkgs.vimPlugins.better-escape-nvim;
        type = "lua";
        config = ''require("plugins.better_escape")'';
      }
      # Devcontainer の起動・接続・終了を Neovim から操作する。
      {
        plugin = pkgs.vimUtils.buildVimPlugin {
          name = "devcontainer-cli.nvim";
          src = inputs.devcontainer-cli-nvim;
          dependencies = [ pkgs.vimPlugins.toggleterm-nvim ];
        };
        type = "lua";
        config = ''require("plugins.devcontainer")'';
      }
      # 各ウインドウにファイル名・アイコン・診断件数を表示する。
      {
        plugin = pkgs.vimPlugins.incline-nvim;
        type = "lua";
        config = ''require("plugins.incline")'';
      }
      # 上流の LSP 定義を使い、共通のサーバー設定を適用する。
      {
        plugin = pkgs.vimPlugins.nvim-lspconfig;
        type = "lua";
        config = ''require("config.lsp").setup()'';
      }
      # ファイル検索・Git・ターミナル・画像と PDF のプレビューを設定する。
      {
        plugin = pkgs.vimPlugins.snacks-nvim;
        type = "lua";
        config = ''require("plugins.snacks")'';
      }
      # AI CLI の操作キーとターミナルの配置・サイズ変更を設定する。
      {
        plugin = pkgs.vimPlugins.sidekick-nvim;
        type = "lua";
        config = ''require("plugins.sidekick")'';
      }
      # Markdown を表示用に整形し、切り替えキーを設定する。
      {
        plugin = pkgs.vimPlugins.render-markdown-nvim;
        type = "lua";
        config = ''require("plugins.markdown")'';
      }
    ];
  };
}
