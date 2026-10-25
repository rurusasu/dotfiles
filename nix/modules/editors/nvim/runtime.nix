{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages =
    with pkgs;
    [
      # Configured Neovim plugin runtime.
      neovim-remote
      devcontainer
      imagemagick
      poppler-utils
      # Language servers and formatters used by the Neovim configuration.
      nixd
      nixfmt
      ty
      ruff
      yaml-language-server
      taplo
      bash-language-server
      lua-language-server
      stylua
      marksman
      # The Go/Rust language servers execute these toolchains from PATH.
      go
      rustup
      gopls
      (lib.hiPrio rust-analyzer)
      (lib.hiPrio rustfmt)
      oxlint
      typescript-language-server
      typescript
      astro-language-server
      prisma-language-server
    ]
    ++ (pkgs.neovimUtils.makeVimPackageInfo (
      map (
        plugin: if plugin ? plugin then builtins.removeAttrs plugin [ "runtime" ] else plugin
      ) config.programs.neovim.plugins
    )).runtimeDeps;
}
