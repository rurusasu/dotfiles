# Single Source of Truth for all packages across platforms.
# Each entry defines: nix derivation, optional Windows package IDs, category.
#
# Exported attributes:
#   - catalog categories (core, dev, terminal, editors, llm, …) → lists of derivations
#   - all                → flat list of all derivations
#   - wingetMap          → nix attr name → winget PackageIdentifier
#   - msstoreMap         → nix attr name → Microsoft Store Product ID
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
#   - supportReport      → per-package Windows/Darwin/Linux provider metadata
#   - darwinCasks        → Homebrew casks derived from provider metadata
#   - darwinBrews        → Homebrew formulas derived from provider metadata
#   - linuxSystemModules → system-layer capabilities required on Linux
#   - providerErrors     → unresolved provider metadata (must remain empty)
#   - windowsOnly        → packages with no nix equivalent (winget/msstore/npm/pnpm)
#
# Imported by:
#   - nix/flakes/packages.nix → perSystem buildEnv outputs
#   - nix/home/packages.nix   → home.packages
#   - nix/packages/winget.nix → winget/npm/pnpm JSON generation
{
  pkgs,
  lib,
}:
let
  rawCatalog = {
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
    netcat = {
      pkg = pkgs.netcat;
      winget = null;
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
    nodejs = {
      pkg = pkgs.nodejs;
      winget = "OpenJS.NodeJS.LTS";
      category = "dev";
    };
    python3 = {
      pkg = pkgs.python3;
      winget = null;
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
      pkg = pkgs.gwq;
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
    dprint = {
      pkg = pkgs.dprint;
      winget = "dprint.dprint";
      category = "dev";
    };
    hadolint = {
      pkg = pkgs.hadolint;
      winget = "hadolint.hadolint";
      category = "dev";
    };
    bun = {
      pkg = pkgs.bun;
      winget = "Oven-sh.Bun";
      category = "dev";
    };
    zig = {
      pkg = pkgs.zig;
      winget = "zig.zig";
      category = "dev";
    };

    # ── terminal ──────────────────────────────────────────
    wezterm = {
      pkg = if pkgs.stdenv.hostPlatform.isDarwin then null else pkgs.wezterm;
      winget = "wez.wezterm.nightly";
      category = "terminal";
      support = {
        darwin = {
          provider = "homebrew-cask";
          cask = "wezterm@nightly";
        };
        linux = {
          provider = "nix";
        };
      };
    };
    hammerspoon = {
      winget = null;
      category = "terminal";
      support = {
        darwin = {
          provider = "homebrew-cask";
          cask = "hammerspoon";
        };
        linux = {
          unsupported = "Hammerspoon is only available on macOS";
        };
        windows = {
          unsupported = "Hammerspoon is only available on macOS";
        };
      };
    };
    autohotkey = {
      winget = "AutoHotkey.AutoHotkey";
      category = "terminal";
      support = {
        darwin = {
          unsupported = "AutoHotkey is only available on Windows";
        };
        linux = {
          unsupported = "AutoHotkey is only available on Windows";
        };
        windows = {
          provider = "winget";
        };
      };
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
    vscode = {
      # VS Code 1.129.1's macOS arm64 archive omits the bundled ripgrep
      # binary, so use the separately packaged ripgrep instead.
      pkg = (pkgs.vscode.override { useVSCodeRipgrep = false; }).overrideAttrs (
        old:
        if pkgs.stdenv.hostPlatform.isDarwin then
          {
            postPatch =
              lib.replaceStrings
                [
                  "rm Contents/Resources/app/node_modules/@vscode/ripgrep-universal/bin/darwin-arm64/rg\nln -s"
                ]
                [
                  "rm -f Contents/Resources/app/node_modules/@vscode/ripgrep-universal/bin/darwin-arm64/rg\nmkdir -p Contents/Resources/app/node_modules/@vscode/ripgrep-universal/bin/darwin-arm64\nln -s"
                ]
                old.postPatch;
          }
        else
          { }
      );
      winget = "Microsoft.VisualStudioCode";
      category = "editors";
      support = {
        darwin = {
          provider = "homebrew-cask";
          cask = "visual-studio-code";
        };
      };
    };

    # ── fonts ─────────────────────────────────────────────
    udev-gothic-nf = {
      pkg = pkgs.udev-gothic-nf;
      winget = null;
      category = "fonts";
    };

    # ── llm ───────────────────────────────────────────────
    codex = {
      pkg = pkgs.codex;
      winget = "OpenAI.Codex";
      category = "llm";
    };
    chatgpt = {
      pkg = if pkgs.stdenv.hostPlatform.isLinux then pkgs.callPackage ./chatgpt { } else null;
      msstore = "9NT1R1C2HH7J";
      category = "desktop";
      support = {
        darwin = {
          provider = "homebrew-cask";
          cask = "chatgpt";
        };
        linux = {
          provider = "nix";
        };
      };
    };
    ollama = {
      pkg = if pkgs.stdenv.hostPlatform.isDarwin then null else pkgs.ollama;
      winget = "Ollama.Ollama";
      category = "llm";
      installFeature = "WithOllama";
      support = {
        darwin = {
          provider = "homebrew-cask";
          cask = "ollama-app";
        };
        linux = {
          provider = "nix";
        };
      };
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

    # ── desktop applications ──────────────────────────────
    discord = {
      pkg = if pkgs.stdenv.hostPlatform.isDarwin then null else pkgs.discord;
      winget = "Discord.Discord";
      category = "desktop";
      installFeature = "WithHermes";
      support = {
        darwin = {
          provider = "homebrew-cask";
          cask = "discord";
        };
        linux = {
          provider = "nix";
        };
      };
    };
    _1password-gui = {
      pkg = pkgs._1password-gui;
      winget = "AgileBits.1Password";
      category = "desktop";
      support = {
        darwin = {
          provider = "homebrew-cask";
          cask = "1password";
        };
      };
    };
    arc-browser = {
      winget = "TheBrowserCompany.Arc";
      category = "desktop";
      support = {
        windows = {
          provider = "winget";
        };
        darwin = {
          unsupported = "Use Dia instead of Arc on macOS";
        };
        linux = {
          unsupported = "Vendor does not publish a Linux build";
        };
      };
    };
    dia-browser = {
      category = "desktop";
      support = {
        windows = {
          unsupported = "Vendor currently ships Dia for macOS only";
        };
        darwin = {
          provider = "homebrew-cask";
          cask = "thebrowsercompany-dia";
        };
        linux = {
          unsupported = "Vendor currently ships Dia for macOS only";
        };
      };
    };
    google-chrome = {
      pkg = pkgs.google-chrome;
      winget = "Google.Chrome";
      category = "desktop";
      installFeature = "WithHermes";
      support = {
        darwin = {
          provider = "homebrew-cask";
          cask = "google-chrome";
        };
      };
    };
    orca-editor = {
      winget = "StablyAI.Orca";
      category = "desktop";
      support = {
        darwin = {
          provider = "homebrew-cask";
          cask = "stablyai/orca/orca";
        };
        linux = {
          unsupported = "No reviewed Linux desktop package provider is selected";
        };
      };
    };
    raycast = {
      category = "desktop";
      support = {
        windows = {
          unsupported = "Managed only on macOS in this dotfiles profile";
        };
        darwin = {
          provider = "homebrew-cask";
          cask = "raycast";
        };
        linux = {
          unsupported = "Vendor does not publish a Linux build";
        };
      };
    };
    # ── system capabilities ───────────────────────────────
    tart = {
      category = "system";
      support = {
        windows = {
          unsupported = "Tart requires Apple Silicon macOS";
        };
        darwin = {
          provider = "homebrew-formula";
          formula = "openai/tools/tart";
        };
        linux = {
          unsupported = "Tart requires Apple Silicon macOS";
        };
      };
    };
    docker-desktop = {
      winget = "Docker.DockerDesktop";
      category = "system";
      installFeature = "WithDocker";
      support = {
        windows = {
          provider = "winget";
        };
        darwin = {
          provider = "homebrew-cask";
          cask = "docker-desktop";
        };
        linux = {
          provider = "system-manager";
          systemModule = "docker";
        };
      };
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
      winget = "LuaLS.lua-language-server";
      category = "lsp";
    };
    stylua = {
      pkg = pkgs.stylua;
      winget = "JohnnyMorganz.StyLua";
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

  supports =
    package: system:
    package != null && builtins.elem system (package.meta.platforms or lib.platforms.all);

  # Provider gaps are reviewed explicitly. Adding a package without a provider
  # now fails providerErrors until its unsupported platform is listed here.
  reviewedUnsupported = {
    windows = lib.genAttrs [
      "argocd"
      "astro-language-server"
      "bash-language-server"
      "bat"
      "bats"
      "cilium-cli"
      "cmake"
      "dive"
      "ghostscript"
      "gnumake"
      "gopls"
      "gwq"
      "k9s"
      "kind"
      "kubectl"
      "kubectx"
      "kubernetes-helm"
      "kubeseal"
      "kustomize"
      "marksman"
      "netcat"
      "neovim-remote"
      "nixd"
      "p7zip"
      "pnpm"
      "pre-commit"
      "python3"
      "rustfmt"
      "sops"
      "stern"
      "tmux"
      "treefmt"
      "trivy"
      "typescript-language-server"
      "udev-gothic-nf"
      "unzip"
      "workmux"
      "yaml-language-server"
    ] (_: "No reviewed Windows package provider is selected");
    darwin = { };
    linux = { };
  };

  reviewedUnsupportedFor = platform: name: lib.attrByPath [ platform name ] null reviewedUnsupported;

  defaultSupport =
    name: entry:
    let
      package = entry.pkg or null;
      unsupported = platform: reviewedUnsupportedFor platform name;
    in
    {
      windows =
        if (entry.winget or null) != null then
          { provider = "winget"; }
        else if (entry.msstore or null) != null then
          { provider = "msstore"; }
        else if (entry.npm or null) != null then
          { provider = "npm"; }
        else
          let
            reason = unsupported "windows";
          in
          if reason == null then { } else { unsupported = reason; };
      darwin =
        if supports package "aarch64-darwin" || supports package "x86_64-darwin" then
          { provider = "nix"; }
        else
          let
            reason = unsupported "darwin";
          in
          if reason == null then { } else { unsupported = reason; };
      linux =
        if supports package "x86_64-linux" || supports package "aarch64-linux" then
          { provider = "nix"; }
        else
          let
            reason = unsupported "linux";
          in
          if reason == null then { } else { unsupported = reason; };
    };

  providerSource =
    provider:
    {
      nix = "nixpkgs";
      "homebrew-cask" = "homebrew";
      "homebrew-formula" = "homebrew";
      winget = "winget";
      msstore = "msstore";
      npm = "npm";
      "system-manager" = "nixpkgs";
    }
    .${provider} or null;

  providerIdentity =
    name: entry: platformData:
    let
      provider = platformData.provider or null;
    in
    if provider == "homebrew-cask" then
      platformData.cask or name
    else if provider == "homebrew-formula" then
      platformData.formula or name
    else if provider == "winget" then
      entry.winget or name
    else if provider == "msstore" then
      entry.msstore or name
    else if provider == "npm" then
      entry.npm or name
    else if provider == "system-manager" then
      platformData.systemModule or name
    else
      name;

  normalizeProviderMetadata =
    name: entry: support:
    lib.mapAttrs (
      _: platformData:
      let
        provider = platformData.provider or null;
      in
      if provider == null then
        platformData
      else
        {
          source = providerSource provider;
          identity = providerIdentity name entry platformData;
        }
        // lib.optionalAttrs (provider == "nix" || provider == "system-manager") {
          nixAttr = platformData.nixAttr or (platformData.systemModule or name);
        }
        // platformData
    ) support;

  catalog = lib.mapAttrs (
    name: entry:
    entry
    // {
      support = normalizeProviderMetadata name entry (
        defaultSupport name entry // (entry.support or { })
      );
    }
  ) rawCatalog;

  mkWindowsOnlySupport = provider: reason: {
    windows = {
      inherit provider;
      identity = reason;
      source = providerSource provider;
    };
    darwin = {
      unsupported = reason;
    };
    linux = {
      unsupported = reason;
    };
  };

  windowsOnlySupport = {
    "GitHub.Copilot" = mkWindowsOnlySupport "winget" "Windows application package";
    "Microsoft.PowerToys" = mkWindowsOnlySupport "winget" "Windows system utility";
    "Microsoft.VCRedist.2015+.x64" = mkWindowsOnlySupport "winget" "Windows runtime component";
    "Microsoft.VisualStudio.2022.BuildTools" =
      mkWindowsOnlySupport "winget" "Windows compiler toolchain";
    "Microsoft.WindowsTerminal" = mkWindowsOnlySupport "winget" "Windows shell host";
    "Microsoft.WSL" = mkWindowsOnlySupport "winget" "Windows subsystem component";
    "9PLM9XGG6VKS" = mkWindowsOnlySupport "msstore" "Windows Store desktop application";
  };

  # Group package names by category
  grouped = lib.groupBy (name: catalog.${name}.category) (lib.attrNames catalog);

  platformKey =
    if pkgs.stdenv.hostPlatform.isDarwin then
      "darwin"
    else if pkgs.stdenv.hostPlatform.isLinux then
      "linux"
    else
      "windows";

  featureEnabled =
    enabledFeatures: entry:
    !(entry ? installFeature)
    || entry.installFeature == null
    || enabledFeatures == null
    || builtins.elem entry.installFeature enabledFeatures;

  # Resolve catalog IDs to Nix derivations selected for the current platform.
  resolveForInstallFeatures =
    enabledFeatures: names:
    builtins.filter (p: p != null) (
      map (
        name:
        let
          entry = catalog.${name};
          package = entry.pkg or null;
          provider = entry.support.${platformKey}.provider or null;
        in
        if
          provider == "nix"
          && featureEnabled enabledFeatures entry
          && package != null
          && supports package pkgs.stdenv.hostPlatform.system
        then
          package
        else
          null
      ) names
    );

  resolve = resolveForInstallFeatures null;

  # Extract winget mappings (non-null only)
  wingetMap = lib.filterAttrs (_: v: v != null) (lib.mapAttrs (_: v: v.winget or null) catalog);
  wingetFeatureMap = lib.filterAttrs (_: v: v != null) (
    lib.mapAttrs (_: v: v.installFeature or null) catalog
  );
  msstoreMap = lib.filterAttrs (_: v: v != null) (lib.mapAttrs (_: v: v.msstore or null) catalog);
  npmMap = lib.filterAttrs (_: v: v != null) (lib.mapAttrs (_: v: v.npm or null) catalog);

  supportReport = lib.mapAttrs (_: entry: entry.support) catalog // windowsOnlySupport;
  darwinCasks = lib.mapAttrsToList (_: entry: entry.support.darwin.cask or null) (
    lib.filterAttrs (
      _: entry:
      (entry.support.darwin.provider or null) == "homebrew-cask"
      && (entry.support.darwin.cask or null) != null
    ) catalog
  );
  darwinCasksForInstallFeatures =
    enabledFeatures:
    lib.mapAttrsToList (_: entry: entry.support.darwin.cask or null) (
      lib.filterAttrs (
        _: entry:
        (entry.support.darwin.provider or null) == "homebrew-cask"
        && (entry.support.darwin.cask or null) != null
        && featureEnabled enabledFeatures entry
      ) catalog
    );
  darwinBrews = lib.mapAttrsToList (_: entry: entry.support.darwin.formula or null) (
    lib.filterAttrs (
      _: entry:
      (entry.support.darwin.provider or null) == "homebrew-formula"
      && (entry.support.darwin.formula or null) != null
    ) catalog
  );
  linuxSystemModules = lib.mapAttrsToList (_: entry: entry.support.linux.systemModule or null) (
    lib.filterAttrs (
      _: entry:
      (entry.support.linux.provider or null) == "system-manager"
      && (entry.support.linux.systemModule or null) != null
    ) catalog
  );
  darwinPackage =
    name: entry:
    let
      support = entry.support.darwin;
      provider = support.provider;
    in
    if provider == "nix" then
      entry.pkg
    else
      pkgs.writeText "darwin-${name}-provider.json" (
        builtins.toJSON {
          inherit provider;
          source = support.source;
          identity = support.identity;
        }
      );
  darwinPackages = lib.mapAttrs darwinPackage (
    lib.filterAttrs (
      _: entry:
      let
        provider = entry.support.darwin.provider or null;
      in
      if provider == "nix" then
        (entry.pkg or null) != null && supports entry.pkg "aarch64-darwin"
      else
        builtins.elem provider [
          "homebrew-cask"
          "homebrew-formula"
        ]
    ) catalog
  );

  providerErrorsFor =
    name: support:
    lib.concatMap
      (
        platform:
        let
          platformData = support.${platform} or { };
          provider = platformData.provider or null;
          unsupported = platformData.unsupported or null;
          entry = catalog.${name} or { };
          package = entry.pkg or null;
          prefix = "${name}: ${platform}: ";
          providerSpecificErrors =
            lib.optional (
              provider == "homebrew-cask" && (platformData.cask or null) == null
            ) "${prefix}homebrew-cask provider requires cask"
            ++ lib.optional (
              provider == "homebrew-formula" && (platformData.formula or null) == null
            ) "${prefix}homebrew-formula provider requires formula"
            ++ lib.optional (
              provider == "winget" && (platformData.identity or null) == null
            ) "${prefix}winget provider requires identity"
            ++ lib.optional (
              provider == "msstore" && (platformData.identity or null) == null
            ) "${prefix}msstore provider requires identity"
            ++ lib.optional (
              provider == "npm" && (platformData.identity or null) == null
            ) "${prefix}npm provider requires identity"
            ++ lib.optional (
              provider == "system-manager" && (platformData.systemModule or null) == null
            ) "${prefix}system-manager provider requires systemModule";
        in
        lib.optional (
          provider == null && (unsupported == null || unsupported == "")
        ) "${prefix}missing provider or reviewed unsupported reason"
        ++ lib.optional (
          provider != null && unsupported != null
        ) "${prefix}provider and unsupported cannot coexist"
        ++ lib.optional (
          provider != null && (platformData.source or null) == null
        ) "${prefix}provider requires source"
        ++ lib.optional (
          provider != null && (platformData.identity or null) == null
        ) "${prefix}provider requires identity"
        ++ lib.optional (
          (platformData.source or null) == "nixpkgs" && (platformData.nixAttr or null) == null
        ) "${prefix}source = nixpkgs requires nixAttr"
        ++ lib.optional (
          provider == "nix" && platform == platformKey && (package == null || !lib.isDerivation package)
        ) "${prefix}nix provider requires a derivation"
        ++ lib.optional (
          provider == "nix"
          && package != null
          && lib.isDerivation package
          && platform == platformKey
          && !supports package pkgs.stdenv.hostPlatform.system
        ) "${prefix}nix provider derivation does not support ${pkgs.stdenv.hostPlatform.system}"
        ++ providerSpecificErrors
      )
      [
        "windows"
        "darwin"
        "linux"
      ];

  darwinNixNames = lib.attrNames (
    lib.filterAttrs (_: entry: (entry.support.darwin.provider or null) == "nix") catalog
  );
  darwinHomebrewNames = lib.attrNames (
    lib.filterAttrs (
      _: entry:
      let
        provider = entry.support.darwin.provider or null;
      in
      provider == "homebrew-cask" || provider == "homebrew-formula"
    ) catalog
  );
  providerErrors =
    lib.concatMap (name: providerErrorsFor name supportReport.${name}) (lib.attrNames supportReport)
    ++ map (name: "${name}: darwin: catalog ID appears in both Nix and Homebrew resolution") (
      lib.intersectLists darwinNixNames darwinHomebrewNames
    );

in
# Category-resolved package lists (auto-derived from catalog)
lib.mapAttrs (_: resolve) grouped
// {
  # Tart guests intentionally receive only the requested CLI tools. WezTerm is
  # installed as a macOS cask because its Nix package is unavailable on Darwin.
  tartMinimal = resolve [
    "git"
    "chezmoi"
    "neovim"
    "codex"
  ];

  # All packages (flat list)
  all = resolve (lib.attrNames catalog);
  allForInstallFeatures =
    enabledFeatures: resolveForInstallFeatures enabledFeatures (lib.attrNames catalog);
  allWithout =
    excludedNames:
    resolve (builtins.filter (name: !(builtins.elem name excludedNames)) (lib.attrNames catalog));
  allWithoutForInstallFeatures =
    enabledFeatures: excludedNames:
    resolveForInstallFeatures enabledFeatures (
      builtins.filter (name: !(builtins.elem name excludedNames)) (lib.attrNames catalog)
    );

  # Windows: nix attr name → winget PackageIdentifier
  inherit
    wingetMap
    wingetFeatureMap
    msstoreMap
    npmMap
    ;

  inherit
    resolveForInstallFeatures
    supportReport
    darwinCasks
    darwinCasksForInstallFeatures
    darwinBrews
    darwinPackages
    linuxSystemModules
    providerErrors
    windowsOnlySupport
    ;

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
    "@deepseek-ai/dsh"
    "@playwright/cli@0.1.14"
    "playwright@1.61.0"
    "typescript-language-server"
    "typescript"
  ];

  pnpmInstallFeature = {
    "@playwright/cli" = "WithHermes";
    playwright = "WithHermes";
  };

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
    "@deepseek-ai/dsh" = {
      command = "dsh";
      args = [ "--version" ];
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
    "@deepseek-ai/dsh" = [
      "--allow-build=@deepseek-ai/dsh-subprocess-local"
      "--allow-build=@google/genai"
      "--allow-build=koffi"
      "--allow-build=node-pty"
      "--allow-build=protobufjs"
    ];
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
    nodejs = {
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
    lua-language-server = {
      command = "lua-language-server";
      args = [ "--version" ];
    };
    stylua = {
      command = "stylua";
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
    ollama = {
      command = "ollama";
      args = [ "--version" ];
    };
    oxlint = {
      command = "oxlint";
      args = [ "--version" ];
    };
    google-cloud-sdk = {
      command = "gcloud";
      args = [ "version" ];
    };
  };

  # Extra winget install arguments for packages that need a specific installer.
  wingetInstallArgs = {
    autohotkey = [
      "--scope"
      "machine"
    ];
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

  wingetDirectInstallers = { };

  # Packages kept in the catalog but skipped by the normal Windows installer.
  wingetSkipInstall = { };

  # Upstream installers and Microsoft Store installs can drift, require
  # elevation, or hang in CI. Avoid making CI depend on their live behavior.
  wingetCiSkipInstall = {
    google-cloud-sdk = true;
    wezterm = true;
    "9PLM9XGG6VKS" = true;
    "StablyAI.Orca" = true;
  };

  # Extra PATH directories for installers that do not register CLI commands on PATH.
  # Entries may contain Windows environment variables and glob wildcards.
  wingetPathEntries = {
    _1password-cli = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\AgileBits.1Password.CLI*" ];
    "AgileBits.1Password.CLI" = [
      "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\AgileBits.1Password.CLI*"
    ];
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
    "OpenAI.Codex" = {
      linkName = "codex.exe";
      targetPattern = "codex-x86_64-pc-windows-msvc.exe";
    };
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
      "GitHub.Copilot"
      "Microsoft.PowerToys"
      "Microsoft.VCRedist.2015+.x64"
      "Microsoft.VisualStudio.2022.BuildTools"
      "Microsoft.WindowsTerminal"
      "Microsoft.WSL"
    ];
    msstore = [
      "9PLM9XGG6VKS"
    ];
    npm = [
      "agent-browser@0.29.1"
    ];
    pnpm = [
      "@google/gemini-cli"
    ];
  };
}
