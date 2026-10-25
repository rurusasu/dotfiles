# Unix package installation and platform-specific desktop selectors.
let
  linuxDesktop =
    {
      lib,
      pkgs,
      ...
    }:
    {
      imports = [
        (import ./browsers/chrome).homeManager
      ];
      home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        pkgs.obsidian
        pkgs._1password-gui
        pkgs.nautilus
      ];
    };
  chatgptModule = import ./ai_agents/chatgpt;
  chatgptCli =
    { pkgs, ... }:
    {
      programs.codex.enable = true;
      home.packages = [ (chatgptModule.packages { inherit pkgs; }).codex ];
    };
in
{
  homeManager =
    {
      config,
      inputs,
      lib,
      pkgs,
      ...
    }:
    let
      mcpPackages = import ./ai_agents/mcp-packages.nix { inherit inputs pkgs; };
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
        mcp.enable = true;
        hermes-agent = {
          enable = true;
          desktop.enable = true;
        };
      };

      home.packages =
        with pkgs;
        [
          # Applications without native Home Manager installation options.
          inputs.llm-agents.packages.${stdenv.hostPlatform.system}.orca
          comfyui
          # CLI packages without a native Home Manager installation option.
          gh
          yq-go
          mcpPackages.xurl
          mcpPackages.hermes-xapi
          _1password-cli
          ghq
          gwq
          btop
          lazydocker
          inputs.llm-agents.packages.${stdenv.hostPlatform.system}.dsh
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
        ++ (pkgs.neovimUtils.makeVimPackageInfo (
          map (
            plugin: if plugin ? plugin then builtins.removeAttrs plugin [ "runtime" ] else plugin
          ) config.programs.neovim.plugins
        )).runtimeDeps
        ++ lib.optionals stdenv.hostPlatform.isDarwin [
          coreutils
          tart
        ];
    };

  chatgpt =
    { pkgs, ... }:
    {
      imports = [
        chatgptCli
      ];
      home.packages = [ (chatgptModule.packages { inherit pkgs; }).chatgpt ];
    };
  inherit chatgptCli linuxDesktop;

  wslDesktop = { lib, pkgs, ... }: {
    imports = [
      linuxDesktop
      (import ./browsers/chrome).wsl
    ];
    home.packages = lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") [
      pkgs.spotify
      pkgs.signal-desktop
    ];
  };

  darwin = { inputs, pkgs, ... }: {
    environment.systemPackages = [
      # Host integrations such as Orca need GitHub CLI outside the user profile.
      pkgs.gh
      pkgs.obsidian
      pkgs.raycast
      pkgs._1password-gui
      (import ./browsers/dia { inherit inputs pkgs; })
    ];
  };

  nativeDesktop = { pkgs, ... }: {
    home.packages = [
      pkgs.firefox
      pkgs.fuzzel
    ];
  };

  discord =
    { pkgs, lib, ... }:
    {
      programs.discord.enable = lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.discord;
    };
  aerospace = _: { programs.aerospace.enable = true; };
  ghostty = _: { programs.ghostty.enable = true; };
  wezterm = _: { programs.wezterm.enable = true; };
}
