{ pkgs, ... }:
{
  # 全エディタから使えるよう、サーバー・整形ツールを通常の PATH に導入する。
  # Neovim の詳細設定は nvim/lua/config/lsp.lua、Cursor は cursor/ が管理する。
  home.packages = with pkgs; [
    # Nix
    nixd
    nixfmt
    # Python
    ty
    ruff
    # YAML・TOML・シェル
    yaml-language-server
    taplo
    bash-language-server
    # Lua・Markdown
    lua-language-server
    stylua
    marksman
    # Go・Rust
    gopls
    rust-analyzer
    rustfmt
    # JavaScript・TypeScript・Astro・Prisma
    oxlint
    typescript-language-server
    typescript
    astro-language-server
    prisma-language-server
  ];
}
