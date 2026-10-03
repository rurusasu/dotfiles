{ pkgs, ... }:
{
  # サーバー・整形ツールは Nix で導入し、Neovim の PATH に追加する。
  # 起動対象と整形設定は lua/config/lsp.lua で管理する。
  programs.neovim.extraPackages = with pkgs; [
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
