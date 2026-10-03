{ pkgs, ... }:
let
  # nixpkgs にないプラグインは、現在利用しているコミットとハッシュで固定する。
  modes = pkgs.vimUtils.buildVimPlugin {
    pname = "modes.nvim";
    version = "8022c7345e51";
    src = pkgs.fetchFromGitHub {
      owner = "mvllow";
      repo = "modes.nvim";
      rev = "8022c7345e51423b4cc6333971f3cbfb7e6035bc";
      hash = "sha256-17Rwm2QYMAgeavYFUTVy2gbCv3mgD89FKMKndqCbb3A=";
    };
  };
  devcontainer = pkgs.vimUtils.buildVimPlugin {
    pname = "devcontainer-cli.nvim";
    version = "00b08c1dd2b2";
    src = pkgs.fetchFromGitHub {
      owner = "erichlf";
      repo = "devcontainer-cli.nvim";
      rev = "00b08c1dd2b272b5b56b265de148c38d12ea0597";
      hash = "sha256-5ASPCFzVOndi8wbLpmxNJcHpmWGaqC1qgmT7bptZ3+A=";
    };
    dependencies = [ pkgs.vimPlugins.toggleterm-nvim ];
  };
in
{
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
    # 配色を共通の Catppuccin テーマに合わせる。
    {
      plugin = pkgs.vimPlugins.catppuccin-nvim;
      type = "lua";
      config = ''require("plugins.catppuccin").setup()'';
    }
    # ディレクトリをバッファとして編集し、分割表示と隠しファイルに対応する。
    {
      plugin = pkgs.vimPlugins.oil-nvim;
      type = "lua";
      config = ''require("plugins.oil").setup()'';
    }
    # Git の変更箇所を行番号横に表示する。
    {
      plugin = pkgs.vimPlugins.gitsigns-nvim;
      type = "lua";
      config = ''require("plugins.gitsigns").setup()'';
    }
    # 編集モードに応じてカーソル行の色を変える。
    {
      plugin = modes;
      type = "lua";
      config = ''require("plugins.modes").setup()'';
    }
    # キー操作の候補を表示する。
    {
      plugin = pkgs.vimPlugins.which-key-nvim;
      type = "lua";
      config = ''require("plugins.which_key").setup()'';
    }
    # 括弧を補完し、Enter は標準補完のキー設定に任せる。
    {
      plugin = pkgs.vimPlugins.nvim-autopairs;
      type = "lua";
      config = ''require("plugins.autopairs").setup()'';
    }
    # 括弧や引用符の追加・変更・削除を行う。
    {
      plugin = pkgs.vimPlugins.nvim-surround;
      type = "lua";
      config = ''require("plugins.surround").setup()'';
    }
    # インデントの深さをガイド線で表示する。
    {
      plugin = pkgs.vimPlugins.indent-blankline-nvim;
      type = "lua";
      config = ''require("plugins.indent_blankline").setup()'';
    }
    # 挿入・ターミナルモードで jk を押すと通常モードに戻る。
    {
      plugin = pkgs.vimPlugins.better-escape-nvim;
      type = "lua";
      config = ''require("plugins.better_escape").setup()'';
    }
    # Neovim のウインドウと tmux のペインを共通キーで移動する。
    pkgs.vimPlugins.vim-tmux-navigator
    # Devcontainer の起動・接続・終了を Neovim から操作する。
    {
      plugin = devcontainer;
      type = "lua";
      config = ''require("plugins.devcontainer").setup()'';
    }
    # 各ウインドウにファイル名・アイコン・診断件数を表示する。
    {
      plugin = pkgs.vimPlugins.incline-nvim;
      type = "lua";
      config = ''require("plugins.incline").setup()'';
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
      config = ''require("plugins.snacks").setup()'';
    }
    # AI CLI の操作キーとターミナルの配置・サイズ変更を設定する。
    {
      plugin = pkgs.vimPlugins.sidekick-nvim;
      type = "lua";
      config = ''require("plugins.sidekick").setup()'';
    }
    # Markdown を表示用に整形し、切り替えキーを設定する。
    {
      plugin = pkgs.vimPlugins.render-markdown-nvim;
      type = "lua";
      config = ''require("plugins.markdown").setup()'';
    }
  ];
}
