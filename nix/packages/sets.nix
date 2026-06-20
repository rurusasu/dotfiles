# Single Source of Truth for all packages across platforms.
# Each entry defines: nix derivation, optional Windows package IDs, category.
#
# Exported attributes:
#   - catalog categories (core, dev, terminal, editors, llm, …) → lists of derivations
#   - all                → flat list of all derivations
#   - wingetMap          → nix attr name → winget PackageIdentifier
#   - npmMap             → nix attr name → npm package spec
#   - pnpmGlobal         → cross-platform pnpm global package names
#   - npmVerify          → catalog attr name → { command, args } for npm verification
#   - pnpmVerify         → package name → { command, args } for post-install verification
#   - pnpmPostInstall    → package name → { command, args } to run after pnpm add -g
#   - pnpmInstallArgs    → package name → extra pnpm add -g arguments
#   - wingetVerify       → catalog attr name → { command, args } for post-install verification
#   - msstoreVerifyById  → Microsoft Store Product ID → { command, args } for post-install verification
#   - wingetInstallArgs  → catalog attr name → extra winget install arguments
#   - wingetInstallTimeoutSeconds → catalog attr name or winget ID → winget install timeout
#   - wingetDirectInstallers → catalog attr name or winget ID → direct installer metadata
#   - wingetSkipInstall → catalog attr name or winget/msstore ID → skip normal automated install
#   - wingetCiSkipInstall → catalog attr name or winget/msstore ID → skip CI winget install smoke test
#   - wingetPathEntries  → catalog attr name or winget ID → extra Windows PATH directories
#   - windowsOnly        → packages with no nix equivalent (winget/msstore/npm/pnpm)
#
# Imported by:
#   - nix/flakes/packages.nix → perSystem buildEnv outputs
#   - nix/home/packages.nix   → home.packages
#   - nix/packages/winget.nix → winget/npm/pnpm JSON generation
{
  pkgs,
  lib,
  gwqSrc ? null,
}:
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
    nodejs_24 = {
      pkg = pkgs.nodejs_24;
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
    rustup = {
      pkg = pkgs.rustup;
      winget = "Rustlang.Rustup";
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
      winget = "x-motemen.ghq";
      category = "dev";
    };
    gwq = {
      pkg = import ./gwq/default.nix (
        { inherit pkgs; } // lib.optionalAttrs (gwqSrc != null) { src = gwqSrc; }
      );
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
      npm = "@devcontainers/cli";
      category = "dev";
    };
    lazygit = {
      pkg = pkgs.lazygit;
      winget = "JesseDuffield.lazygit";
      category = "dev";
    };
    bats = {
      pkg = pkgs.bats;
      winget = null; # Windows 対応せず (NixOS/WSL のみ)
      category = "dev";
    };
    imagemagick = {
      pkg = pkgs.imagemagick;
      winget = "ImageMagick.ImageMagick";
      category = "dev";
    };
    ghostscript = {
      pkg = pkgs.ghostscript;
      winget = null; # winget カタログ未収録 — Windows は https://ghostscript.com から手動インストール
      category = "dev";
    };
    poppler-utils = {
      pkg = pkgs.poppler-utils;
      winget = "oschwartz10612.Poppler";
      category = "dev";
    };

    # ── terminal ──────────────────────────────────────────
    wezterm = {
      pkg = pkgs.wezterm;
      winget = "wez.wezterm.nightly";
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
    neovim-remote = {
      pkg = pkgs.neovim-remote;
      winget = null;
      category = "editors";
    };
    obsidian = {
      pkg = pkgs.obsidian;
      winget = "Obsidian.Obsidian";
      category = "editors";
    };

    # ── fonts ─────────────────────────────────────────────
    udev-gothic-nf = {
      pkg = pkgs.udev-gothic-nf;
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
    workmux = {
      pkg = pkgs.workmux;
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
    ty = {
      pkg = pkgs.ty;
      winget = "astral-sh.ty";
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
      winget = "tamasfe.taplo";
      category = "lsp";
    };
    bash-language-server = {
      pkg = pkgs.bash-language-server;
      winget = null;
      category = "lsp";
    };
    lua-language-server = {
      pkg = pkgs.lua-language-server;
      winget = null;
      category = "lsp";
    };
    stylua = {
      pkg = pkgs.stylua;
      winget = null;
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
      pkg = lib.hiPrio pkgs.rust-analyzer;
      winget = "Rustlang.rust-analyzer";
      category = "lsp";
    };
    rustfmt = {
      pkg = lib.hiPrio pkgs.rustfmt;
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
      winget = "oxc-project.oxlint";
      category = "lsp";
    };
    typescript-language-server = {
      pkg = pkgs.typescript-language-server;
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
  npmMap = lib.filterAttrs (_: v: v != null) (lib.mapAttrs (_: v: v.npm or null) catalog);

in
# Category-resolved package lists (auto-derived from catalog)
lib.mapAttrs (_: names: resolve names) grouped
// {
  # All packages (flat list)
  all = resolve (lib.attrNames catalog);

  # Windows: nix attr name → winget PackageIdentifier
  inherit wingetMap npmMap;

  # Post-install verification commands for npm packages.
  # Keys match catalog attr names from npmMap.
  npmVerify = {
    "agent-browser" = {
      command = "agent-browser";
      args = [ "--version" ];
    };
    devcontainer = {
      command = "devcontainer";
      args = [ "--version" ];
    };
  };

  # Cross-platform pnpm global packages
  pnpmGlobal = [
    "@prisma/language-server"
    "@agentclientprotocol/claude-agent-acp"
    "@playwright/cli@0.1.13"
    "playwright@1.60.0"
    "typescript-language-server"
    "typescript"
  ];

  # Post-install verification commands for pnpm packages.
  # Keys match globalPackages entries. Packages not listed skip verification.
  pnpmVerify = {
    "@prisma/language-server" = {
      command = "prisma-language-server";
      args = [ "--version" ];
    };
    "@google/gemini-cli" = {
      command = "gemini";
      args = [ "--version" ];
    };
    "typescript-language-server" = {
      command = "typescript-language-server";
      args = [ "--version" ];
    };
    "typescript" = {
      command = "tsc";
      args = [ "--version" ];
    };
    "@agentclientprotocol/claude-agent-acp" = {
      type = "commandExists";
      command = "claude-agent-acp";
      args = [ ];
    };
    "@playwright/cli" = {
      command = "playwright-cli";
      args = [ "--version" ];
    };
    "playwright" = {
      command = "playwright";
      args = [ "--version" ];
    };
  };

  # Post-install commands for pnpm packages.
  # Playwright keeps browser binaries outside node_modules by default
  # (%LOCALAPPDATA%/ms-playwright on Windows); this ensures the pnpm-managed
  # CLI also provisions the Chromium runtime used by automation scripts.
  pnpmPostInstall = {
    "playwright" = {
      command = "playwright";
      args = [
        "install"
        "chromium"
      ];
      timeoutSeconds = 600;
    };
  };

  # Extra pnpm install arguments for packages that need approved native builds.
  pnpmInstallArgs = {
    "@google/gemini-cli" = [
      "--allow-build=@github/keytar"
      "--allow-build=node-pty"
    ];
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
    jq = {
      command = "jq";
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
    nodejs_24 = {
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
    rustup = {
      command = "rustup";
      args = [ "--version" ];
    };
    ghq = {
      command = "ghq";
      args = [ "--version" ];
    };
    lazygit = {
      command = "lazygit";
      args = [ "--version" ];
    };
    imagemagick = {
      command = "magick";
      args = [ "--version" ];
    };
    poppler-utils = {
      command = "pdftoppm";
      args = [ "-v" ];
    };
    wezterm = {
      command = "wezterm";
      args = [ "--version" ];
    };
    ty = {
      command = "ty";
      args = [ "--version" ];
    };
    ruff = {
      command = "ruff";
      args = [ "--version" ];
    };
    taplo = {
      command = "taplo";
      args = [ "--version" ];
    };
    rust-analyzer = {
      command = "pwsh";
      args = [
        "-NoProfile"
        "-Command"
        "& (Join-Path $env:LOCALAPPDATA 'Microsoft/WinGet/Links/rust-analyzer.exe') --version"
      ];
    };
    opencode = {
      command = "opencode";
      args = [ "--version" ];
    };
    oxlint = {
      command = "oxlint";
      args = [ "--version" ];
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

  # Extra winget install arguments for packages that need a specific installer.
  wingetInstallArgs = {
    "Microsoft.VisualStudio.2022.BuildTools" = [
      "--override"
      "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive --wait --norestart"
    ];
    powershell = [
      "--installer-type"
      "wix"
    ];
  };

  wingetInstallTimeoutSeconds = {
    google-cloud-sdk = 900;
    "Microsoft.VisualStudio.2022.BuildTools" = 1800;
  };

  wingetDirectInstallers = {
    warp-terminal = {
      type = "warpInnoLatest";
      timeoutSeconds = 900;
      installerArgs = [
        "/VERYSILENT"
        "/SUPPRESSMSGBOXES"
        "/NORESTART"
        "/CURRENTUSER"
      ];
    };
  };

  # Packages kept in the catalog but skipped by the normal Windows installer.
  wingetSkipInstall = { };

  # Upstream nightly winget manifests and Microsoft Store installs can drift or
  # hang in CI. Avoid making CI depend on their live installer behavior.
  wingetCiSkipInstall = {
    wezterm = true;
    warp-terminal = true;
    "9PLM9XGG6VKS" = true;
  };

  # Extra PATH directories for installers that do not register CLI commands on PATH.
  # Entries may contain Windows environment variables and glob wildcards.
  wingetPathEntries = {
    google-cloud-sdk = [
      "%ProgramFiles%\\Google\\Cloud SDK\\google-cloud-sdk\\bin"
      "%ProgramFiles(x86)%\\Google\\Cloud SDK\\google-cloud-sdk\\bin"
      "%LOCALAPPDATA%\\Google\\Cloud SDK\\google-cloud-sdk\\bin"
    ];
    poppler-utils = [
      "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\oschwartz10612.Poppler*\\*\\Library\\bin"
    ];
    rustup = [ "%USERPROFILE%\\.cargo\\bin" ];
    wezterm = [ "%ProgramFiles%\\WezTerm" ];
  };

  # Portable winget packages whose package exe name does not match the command name.
  wingetPortableLinksById = {
    oxlint = {
      linkName = "oxlint.exe";
      targetPattern = "oxlint-*.exe";
    };
    "oxc-project.oxlint" = {
      linkName = "oxlint.exe";
      targetPattern = "oxlint-*.exe";
    };
  };

  # Post-install verification commands for Windows-only winget packages.
  # Keys match PackageIdentifier values because these packages have no catalog attr.
  wingetVerifyById = {
    "dprint.dprint" = {
      command = "dprint";
      args = [ "--version" ];
    };
    "hadolint.hadolint" = {
      command = "hadolint";
      args = [ "--version" ];
    };
    "OpenAI.Codex" = {
      command = "codex";
      args = [ "--version" ];
    };
    "Microsoft.WSL" = {
      command = "wsl";
      args = [ "--version" ];
      timeoutSeconds = 30;
      recoveryStrategy = "wingetRepairThenReinstall";
    };
    "Oven-sh.Bun" = {
      command = "bun";
      args = [ "--version" ];
    };
    "zig.zig" = {
      command = "zig";
      args = [ "version" ];
    };
  };

  # Post-install verification commands for Windows-only Microsoft Store packages.
  # Keys match Microsoft Store Product ID values because these packages have no catalog attr.
  msstoreVerifyById = {
    "9PLM9XGG6VKS" = {
      type = "appxLaunchTarget";
      command = "OpenAI.Codex";
      args = [ "OpenAI.Codex_2p2nqsd0c76g0!App" ];
    };
  };

  # Windows-only packages (no nix equivalent)
  windowsOnly = {
    winget = [
      "AgileBits.1Password"
      "Anthropic.Claude"
      "TheBrowserCompany.Arc"
      "Docker.DockerDesktop"
      "GitHub.Copilot"
      "dprint.dprint"
      "hadolint.hadolint"
      "Google.Chrome"
      "Microsoft.PowerToys"
      "Microsoft.VCRedist.2015+.x64"
      "Microsoft.VisualStudio.2022.BuildTools"
      "Microsoft.VisualStudioCode"
      "Microsoft.WindowsTerminal"
      "Microsoft.WSL"
      "OpenAI.Codex"
      "TablePlus.TablePlus"
      "Oven-sh.Bun"
      "zig.zig"
    ];
    msstore = [
      "9NT1R1C2HH7J"
      "9PLM9XGG6VKS"
    ];
    npm = [
      "agent-browser@0.19.0"
    ];
    pnpm = [
      "@google/gemini-cli"
    ];
  };
}
