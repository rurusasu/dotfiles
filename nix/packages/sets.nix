# Single Source of Truth for all packages across platforms.
# Each entry defines: nix derivation, winget ID (null if none), category.
#
# Exported attributes:
#   - catalog categories (core, dev, terminal, editors, llm, …) → lists of derivations
#   - all                → flat list of all derivations
#   - wingetMap          → nix attr name → winget PackageIdentifier
#   - pnpmGlobal         → cross-platform pnpm global package names
#   - pnpmVerify         → package name → { command, args } for post-install verification
#   - wingetVerify       → catalog attr name → { command, args } for post-install verification
#   - windowsOnly        → packages with no nix equivalent (winget/msstore/pnpm)
#
# Imported by:
#   - nix/flakes/packages.nix → perSystem buildEnv outputs
#   - nix/home/packages.nix   → home.packages
#   - nix/packages/winget.nix → winget/pnpm JSON generation
{ pkgs, lib }:
let
  catalog = {
    # ── core ──────────────────────────────────────────────
    chezmoi = {
      pkg = pkgs.chezmoi;
      winget = "twpayne.chezmoi";
      category = "core";
    };
    git = {
      pkg = pkgs.git;
      winget = "Git.Git";
      category = "core";
    };
    gh = {
      pkg = pkgs.gh;
      winget = "GitHub.cli";
      category = "core";
    };
    fd = {
      pkg = pkgs.fd;
      winget = "sharkdp.fd";
      category = "core";
    };
    ripgrep = {
      pkg = pkgs.ripgrep;
      winget = "BurntSushi.ripgrep.MSVC";
      category = "core";
    };
    bat = {
      pkg = pkgs.bat;
      winget = null;
      category = "core";
    };
    jq = {
      pkg = pkgs.jq;
      winget = "jqlang.jq";
      category = "core";
    };
    eza = {
      pkg = pkgs.eza;
      winget = "eza-community.eza";
      category = "core";
    };
    zoxide = {
      pkg = pkgs.zoxide;
      winget = "ajeetdsouza.zoxide";
      category = "core";
    };
    fzf = {
      pkg = pkgs.fzf;
      winget = "junegunn.fzf";
      category = "core";
    };
    direnv = {
      pkg = pkgs.direnv;
      winget = "direnv.direnv";
      category = "core";
    };
    unzip = {
      pkg = pkgs.unzip;
      winget = null;
      category = "core";
    };
    p7zip = {
      pkg = pkgs.p7zip;
      winget = null;
      category = "core";
    };

    # ── dev ───────────────────────────────────────────────
    nodejs_22 = {
      pkg = pkgs.nodejs_22;
      winget = "OpenJS.NodeJS.LTS";
      category = "dev";
    };
    python3 = {
      pkg = pkgs.python3;
      winget = "Python.Python.3.13";
      category = "dev";
    };
    go = {
      pkg = pkgs.go;
      winget = "GoLang.Go";
      category = "dev";
    };
    gnumake = {
      pkg = pkgs.gnumake;
      winget = null;
      category = "dev";
    };
    cmake = {
      pkg = pkgs.cmake;
      winget = null;
      category = "dev";
    };
    ghq = {
      pkg = pkgs.ghq;
      winget = null;
      category = "dev";
    };
    uv = {
      pkg = pkgs.uv;
      winget = "astral-sh.uv";
      category = "dev";
    };
    pnpm = {
      pkg = pkgs.pnpm;
      winget = null;
      category = "dev";
    };
    devcontainer = {
      pkg = pkgs.devcontainer;
      winget = null;
      category = "dev";
    };

    # ── terminal ──────────────────────────────────────────
    wezterm = {
      pkg = pkgs.wezterm;
      winget = "wez.wezterm";
      category = "terminal";
    };
    tmux = {
      pkg = pkgs.tmux;
      winget = null;
      category = "terminal";
    };
    starship = {
      pkg = pkgs.starship;
      winget = "Starship.Starship";
      category = "terminal";
    };
    warp-terminal = {
      pkg = pkgs.warp-terminal;
      winget = "Warp.Warp";
      category = "terminal";
    };

    # ── editors ───────────────────────────────────────────
    neovim = {
      pkg = pkgs.neovim;
      winget = "Neovim.Neovim";
      category = "editors";
    };
    obsidian = {
      pkg = pkgs.obsidian;
      winget = "Obsidian.Obsidian";
      category = "editors";
    };

    # ── fonts ─────────────────────────────────────────────
    moralerspace = {
      pkg = pkgs.moralerspace-hwjpdoc;
      winget = null;
      category = "fonts";
    };

    # ── llm ───────────────────────────────────────────────
    claude-code = {
      pkg = pkgs.claude-code;
      winget = null;
      category = "llm";
    };
    codex = {
      pkg = pkgs.codex;
      winget = null;
      category = "llm";
    };

    # ── communication ─────────────────────────────────────
    slack = {
      pkg = pkgs.slack;
      winget = "SlackTechnologies.Slack";
      category = "communication";
    };

    # ── k8s ───────────────────────────────────────────────
    kind = {
      pkg = pkgs.kind;
      winget = null;
      category = "k8s";
    };
    kubectl = {
      pkg = pkgs.kubectl;
      winget = null;
      category = "k8s";
    };
    kubernetes-helm = {
      pkg = pkgs.kubernetes-helm;
      winget = null;
      category = "k8s";
    };
    k9s = {
      pkg = pkgs.k9s;
      winget = null;
      category = "k8s";
    };
    kubectx = {
      pkg = pkgs.kubectx;
      winget = null;
      category = "k8s";
    };
    kustomize = {
      pkg = pkgs.kustomize;
      winget = null;
      category = "k8s";
    };
    stern = {
      pkg = pkgs.stern;
      winget = null;
      category = "k8s";
    };
    argocd = {
      pkg = pkgs.argocd;
      winget = null;
      category = "k8s";
    };
    cilium-cli = {
      pkg = pkgs.cilium-cli;
      winget = null;
      category = "k8s";
    };
    kubeseal = {
      pkg = pkgs.kubeseal;
      winget = null;
      category = "k8s";
    };
    sops = {
      pkg = pkgs.sops;
      winget = null;
      category = "k8s";
    };
    trivy = {
      pkg = pkgs.trivy;
      winget = null;
      category = "k8s";
    };
    dive = {
      pkg = pkgs.dive;
      winget = null;
      category = "k8s";
    };

    # ── infra ─────────────────────────────────────────────
    go-task = {
      pkg = pkgs.go-task;
      winget = "Task.Task";
      category = "infra";
    };
    treefmt = {
      pkg = pkgs.treefmt;
      winget = null;
      category = "infra";
    };
    pre-commit = {
      pkg = pkgs.pre-commit;
      winget = null;
      category = "infra";
    };
    powershell = {
      pkg = pkgs.powershell;
      winget = "Microsoft.PowerShell";
      category = "infra";
    };
    _1password-cli = {
      pkg = pkgs._1password-cli;
      winget = "AgileBits.1Password.CLI";
      category = "infra";
    };
    opencode = {
      pkg = pkgs.opencode;
      winget = "SST.opencode";
      category = "infra";
    };
    google-cloud-sdk = {
      pkg = pkgs.google-cloud-sdk;
      winget = "Google.CloudSDK";
      category = "infra";
    };

    # ── lsp ───────────────────────────────────────────────
    nixd = {
      pkg = pkgs.nixd;
      winget = null;
      category = "lsp";
    };
    ruff = {
      pkg = pkgs.ruff;
      winget = "astral-sh.ruff";
      category = "lsp";
    };
    yaml-language-server = {
      pkg = pkgs.yaml-language-server;
      winget = null;
      category = "lsp";
    };
    taplo = {
      pkg = pkgs.taplo;
      winget = null;
      category = "lsp";
    };
    bash-language-server = {
      pkg = pkgs.bash-language-server;
      winget = null;
      category = "lsp";
    };
    lua-language-server = {
      pkg = pkgs.lua-language-server;
      winget = "LuaLS.lua-language-server";
      category = "lsp";
    };
    marksman = {
      pkg = pkgs.marksman;
      winget = null;
      category = "lsp";
    };
    gopls = {
      pkg = pkgs.gopls;
      winget = null;
      category = "lsp";
    };
    rust-analyzer = {
      pkg = pkgs.rust-analyzer;
      winget = null;
      category = "lsp";
    };
    typescript-language-server = {
      pkg = pkgs.typescript-language-server;
      winget = null;
      category = "lsp";
    };
    astro-language-server = {
      pkg = pkgs.astro-language-server;
      winget = null;
      category = "lsp";
    };
    oxlint = {
      pkg = pkgs.oxlint;
      winget = null;
      category = "lsp";
    };
  };

  # Group package names by category
  grouped = lib.groupBy (name: catalog.${name}.category) (lib.attrNames catalog);

  # Resolve attr names to derivations, filtering by platform availability
  resolve =
    names:
    builtins.filter (p: p != null) (
      map (
        n:
        let
          p = catalog.${n}.pkg;
        in
        if builtins.elem pkgs.stdenv.hostPlatform.system (p.meta.platforms or lib.platforms.all) then
          p
        else
          null
      ) names
    );

  # Extract winget mappings (non-null only)
  wingetMap = lib.filterAttrs (_: v: v != null) (lib.mapAttrs (_: v: v.winget) catalog);

in
# Category-resolved package lists (auto-derived from catalog)
lib.mapAttrs (_: names: resolve names) grouped
// {
  # All packages (flat list)
  all = resolve (lib.attrNames catalog);

  # Windows: nix attr name → winget PackageIdentifier
  inherit wingetMap;

  # Cross-platform pnpm global packages
  pnpmGlobal = [
    "@tobilu/qmd"
    "@prisma/language-server"
    "@agentclientprotocol/claude-agent-acp"
    "typescript-language-server"
    "yaml-language-server"
  ];

  # Post-install verification commands for pnpm packages.
  # Keys match globalPackages entries. Packages not listed skip verification.
  pnpmVerify = {
    "@tobilu/qmd" = {
      command = "qmd";
      args = [ "status" ];
    };
    "@prisma/language-server" = {
      command = "prisma-language-server";
      args = [ "--version" ];
    };
    "@google/gemini-cli" = {
      command = "gemini";
      args = [ "--version" ];
    };
    "@agentclientprotocol/claude-agent-acp" = {
      command = "claude-agent-acp";
      args = [ "--version" ];
    };
  };

  # Post-install verification commands for winget packages.
  # Keys match catalog attr names. GUI-only packages are omitted.
  wingetVerify = {
    chezmoi = {
      command = "chezmoi";
      args = [ "--version" ];
    };
    git = {
      command = "git";
      args = [ "--version" ];
    };
    gh = {
      command = "gh";
      args = [ "--version" ];
    };
    fd = {
      command = "fd";
      args = [ "--version" ];
    };
    ripgrep = {
      command = "rg";
      args = [ "--version" ];
    };
    eza = {
      command = "eza";
      args = [ "--version" ];
    };
    zoxide = {
      command = "zoxide";
      args = [ "--version" ];
    };
    fzf = {
      command = "fzf";
      args = [ "--version" ];
    };
    direnv = {
      command = "direnv";
      args = [ "--version" ];
    };
    starship = {
      command = "starship";
      args = [ "--version" ];
    };
    neovim = {
      command = "nvim";
      args = [ "--version" ];
    };
    nodejs_22 = {
      command = "node";
      args = [ "--version" ];
    };
    uv = {
      command = "uv";
      args = [ "--version" ];
    };
    _1password-cli = {
      command = "op";
      args = [ "--version" ];
    };
    powershell = {
      command = "pwsh";
      args = [ "--version" ];
    };
    go-task = {
      command = "task";
      args = [ "--version" ];
    };
    go = {
      command = "go";
      args = [ "version" ];
    };
    python3 = {
      command = "python";
      args = [ "--version" ];
    };
    google-cloud-sdk = {
      command = "gcloud";
      args = [ "version" ];
    };
  };

  # Windows-only packages (no nix equivalent)
  windowsOnly = {
    winget = [
      "AgileBits.1Password"
      "Anthropic.Claude"
      "Anysphere.Cursor"
      "TheBrowserCompany.Arc"
      "Docker.DockerDesktop"
      "GitHub.Copilot"
      "dprint.dprint"
      "hadolint.hadolint"
      "Google.Chrome"
      "Google.Antigravity"
      "Microsoft.PowerToys"
      "Microsoft.VCRedist.2015+.x64"
      "Microsoft.VisualStudioCode"
      "Microsoft.WindowsTerminal"
      "Microsoft.WSL"
      "OpenAI.Codex"
      "TablePlus.TablePlus"
      "Oven-sh.Bun"
      "ZedIndustries.Zed"
      "zig.zig"
    ];
    msstore = [
      "9NT1R1C2HH7J"
    ];
    pnpm = [
      "@google/gemini-cli"
    ];
  };
}
