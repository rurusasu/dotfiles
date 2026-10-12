# Unix CLI installation entrypoint. Feature modules own settings and integration.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  hermesBootstrap = import ./ai_agents/hermes/bootstrap.nix {
    inherit
      config
      inputs
      lib
      pkgs
      ;
  };
  neovimRuntimeDependencies =
    (pkgs.neovimUtils.makeVimPackageInfo (
      map (
        plugin: if plugin ? plugin then builtins.removeAttrs plugin [ "runtime" ] else plugin
      ) config.programs.neovim.plugins
    )).runtimeDeps;
in
{
  programs = {
    home-manager.enable = true;
    bash.enable = true;
    zsh.enable = true;
    git.enable = true;
    ssh.enable = true;
    bat.enable = true;
    eza.enable = true;
    fd.enable = true;
    fzf.enable = true;
    jq.enable = true;
    ripgrep.enable = true;
    zoxide.enable = true;
    starship.enable = true;
    lazygit.enable = true;
    herdr.enable = true;
    neovim.enable = true;
    direnv.enable = true;
    hermes-agent.enable = true;
  };

  home.packages =
    with pkgs;
    [
      # Install CLI packages directly when their configuration remains user-managed.
      gh
      _1password-cli
      ghq
      inputs.llm-agents.packages.${stdenv.hostPlatform.system}.dsh
      hermesBootstrap
      # Public Gmail OAuth task invokes npx; Hermes supplies its private Node runtime.
      nodejs
      # User Python runtimes are managed by uv, without a global Python installation.
      uv
      # Repository Taskfile commands and developer hooks.
      go-task
      pre-commit
      powershell
      bats
      # Configured Neovim plugin runtime.
      neovim-remote
      devcontainer
      imagemagick
      poppler-utils
      # Shared language servers and formatters.
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
    ++ neovimRuntimeDependencies
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      coreutils
      tart
    ];
}
