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
  catalogOverride ? null,
  hermesDesktopPackage ? null,
}:
let
  darwinProviderCandidates = import ./darwin-provider-candidates.nix;
  darwinProviderCandidate = name: darwinProviderCandidates.${name};
  selectDarwinPackage =
    name: customPackage:
    let
      candidate = darwinProviderCandidate name;
    in
    if candidate.source == "nixpkgs" then builtins.getAttr candidate.nixAttr pkgs else customPackage;
  linuxSystems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
  linuxOnlyPackage =
    package:
    if pkgs.stdenv.hostPlatform.isLinux then
      package
    else
      pkgs.runCommand "linux-package-placeholder" {
        meta.platforms = linuxSystems;
      } "touch $out";
  darwinDiscordPackage =
    if pkgs.stdenv.hostPlatform.isDarwin then
      pkgs.discord.overrideAttrs (old: {
        dontFixup = true;
        postInstall = (old.postInstall or "") + ''
          mkdir -p "$out/share/discord"
          mv "$out/Applications/Discord.app/Contents/Resources/modules" "$out/share/discord/modules"
          substituteInPlace "$out/bin/Discord" \
            --replace-fail \
            "$out/Applications/Discord.app/Contents/Resources/modules" \
            "$out/share/discord/modules"
        '';
      })
    else
      null;
  dockerDesktopPackage =
    if pkgs.stdenv.hostPlatform.isDarwin then
      selectDarwinPackage "docker-desktop" (pkgs.callPackage ./docker-desktop { })
    else
      null;
  rawCatalog =
    if catalogOverride != null then
      catalogOverride
    else
      {
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
          pkg = pkgs.wezterm;
          winget = "wez.wezterm.nightly";
          category = "terminal";
          support = {
            darwin = {
              provider = "nix";
              source = "nixpkgs";
              nixAttr = "wezterm";
              identity = {
                homepage = "https://wezterm.org/";
                appName = "WezTerm.app";
                bundleId = "com.github.wez.wezterm";
                executable = "wezterm-gui";
              };
            };
            linux = {
              provider = "nix";
              source = "nixpkgs";
              identity = "wezterm";
              nixAttr = "wezterm";
            };
          };
          legacyDarwin = {
            provider = "homebrew-cask";
            name = "wezterm@nightly";
          };
        };
        hammerspoon = {
          pkg =
            if pkgs.stdenv.hostPlatform.isDarwin then
              selectDarwinPackage "hammerspoon" (pkgs.callPackage ./hammerspoon { })
            else
              null;
          winget = null;
          category = "terminal";
          support = {
            darwin = {
              provider = "nix";
              source = (darwinProviderCandidate "hammerspoon").source;
              identity = {
                homepage = "https://www.hammerspoon.org/";
                appName = "Hammerspoon.app";
                bundleId = "org.hammerspoon.Hammerspoon";
                executable = "Hammerspoon";
              };
            }
            // lib.optionalAttrs ((darwinProviderCandidate "hammerspoon").nixAttr != null) {
              nixAttr = (darwinProviderCandidate "hammerspoon").nixAttr;
            };
            linux = {
              unsupported = "Hammerspoon is only available on macOS";
            };
            windows = {
              unsupported = "Hammerspoon is only available on macOS";
            };
          };
          legacyDarwin = {
            provider = "homebrew-cask";
            name = "hammerspoon";
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
              source = "winget";
              identity = "AutoHotkey.AutoHotkey";
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
          pkg = pkgs.vscode;
          winget = "Microsoft.VisualStudioCode";
          category = "editors";
          support = {
            darwin = {
              provider = "nix";
              source = "nixpkgs";
              nixAttr = "vscode";
              identity = {
                homepage = "https://code.visualstudio.com/";
                appName = "Visual Studio Code.app";
                bundleId = "com.microsoft.VSCode";
                executable = "Code";
              };
            };
          };
          legacyDarwin = {
            provider = "homebrew-cask";
            name = "visual-studio-code";
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
          pkg = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.chatgpt else pkgs.callPackage ./chatgpt { };
          msstore = "9NT1R1C2HH7J";
          category = "desktop";
          support = {
            darwin = {
              provider = "nix";
              source = "nixpkgs";
              nixAttr = "chatgpt";
              identity = {
                homepage = "https://openai.com/chatgpt/desktop/";
                appName = "ChatGPT.app";
                bundleId = "com.openai.codex";
                executable = "ChatGPT";
              };
            };
            linux = {
              provider = "nix";
              source = "dotfiles";
              identity = "chatgpt";
              nixAttr = "chatgpt";
            };
          };
          legacyDarwin = {
            provider = "homebrew-cask";
            name = "chatgpt";
          };
        };
        ollama = {
          pkg = pkgs.ollama;
          winget = "Ollama.Ollama";
          category = "llm";
          installFeature = "WithOllama";
          support = {
            darwin = {
              provider = "nix";
              source = "nixpkgs";
              nixAttr = "ollama";
              identity = {
                homepage = "https://ollama.com/";
                command = "ollama";
                versionArgs = [ "--version" ];
              };
            };
            linux = {
              provider = "nix";
              source = "nixpkgs";
              identity = "ollama";
              nixAttr = "ollama";
            };
          };
          legacyDarwin = {
            provider = "homebrew-cask";
            name = "ollama-app";
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
          pkg = if pkgs.stdenv.hostPlatform.isDarwin then darwinDiscordPackage else pkgs.discord;
          winget = "Discord.Discord";
          category = "desktop";
          installFeature = "WithHermes";
          support = {
            darwin = {
              provider = "nix";
              source = "nixpkgs";
              nixAttr = "discord";
              identity = {
                homepage = "https://discord.com/";
                appName = "Discord.app";
                bundleId = "com.hnc.Discord";
                executable = "Discord";
              };
            };
            linux = {
              provider = "nix";
              source = "nixpkgs";
              identity = "discord";
              nixAttr = "discord";
            };
          };
          legacyDarwin = {
            provider = "homebrew-cask";
            name = "discord";
          };
        };
        _1password-gui = {
          pkg = pkgs._1password-gui;
          winget = "AgileBits.1Password";
          category = "desktop";
          support = {
            darwin = {
              provider = "nix";
              source = "nixpkgs";
              nixAttr = "_1password-gui";
              identity = {
                homepage = "https://1password.com/";
                appName = "1Password.app";
                bundleId = "com.1password.1password";
                executable = "1Password";
              };
            };
          };
          legacyDarwin = {
            provider = "homebrew-cask";
            name = "1password";
          };
        };
        arc-browser = {
          winget = "TheBrowserCompany.Arc";
          category = "desktop";
          support = {
            windows = {
              provider = "winget";
              source = "winget";
              identity = "TheBrowserCompany.Arc";
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
          pkg =
            if pkgs.stdenv.hostPlatform.isDarwin then
              selectDarwinPackage "dia-browser" (pkgs.callPackage ./dia-browser { })
            else
              null;
          category = "desktop";
          support = {
            windows = {
              unsupported = "Vendor currently ships Dia for macOS only";
            };
            darwin = {
              provider = "nix";
              source = (darwinProviderCandidate "dia-browser").source;
              identity = {
                homepage = "https://www.diabrowser.com/";
                appName = "Dia.app";
                bundleId = "company.thebrowser.dia";
                executable = "Dia";
              };
            }
            // lib.optionalAttrs ((darwinProviderCandidate "dia-browser").nixAttr != null) {
              nixAttr = (darwinProviderCandidate "dia-browser").nixAttr;
            };
            linux = {
              unsupported = "Vendor currently ships Dia for macOS only";
            };
          };
          legacyDarwin = {
            provider = "homebrew-cask";
            name = "thebrowsercompany-dia";
          };
        };
        google-chrome = {
          pkg = pkgs.google-chrome;
          winget = "Google.Chrome";
          category = "desktop";
          installFeature = "WithHermes";
          support = {
            darwin = {
              provider = "nix";
              source = "nixpkgs";
              nixAttr = "google-chrome";
              identity = {
                homepage = "https://www.google.com/chrome/";
                appName = "Google Chrome.app";
                bundleId = "com.google.Chrome";
                executable = "Google Chrome";
              };
            };
          };
          legacyDarwin = {
            provider = "homebrew-cask";
            name = "google-chrome";
          };
        };
        orca-editor = {
          pkg =
            if pkgs.stdenv.hostPlatform.isDarwin then
              selectDarwinPackage "orca-editor" (pkgs.callPackage ./orca-editor { })
            else
              null;
          winget = "StablyAI.Orca";
          category = "desktop";
          support = {
            darwin = {
              provider = "nix";
              source = (darwinProviderCandidate "orca-editor").source;
              identity = {
                homepage = "https://onorca.dev/";
                appName = "Orca.app";
                bundleId = "com.stablyai.orca";
                executable = "Orca";
              };
            }
            // lib.optionalAttrs ((darwinProviderCandidate "orca-editor").nixAttr != null) {
              nixAttr = (darwinProviderCandidate "orca-editor").nixAttr;
            };
            linux = {
              unsupported = "No reviewed Linux desktop package provider is selected";
            };
          };
          legacyDarwin = {
            provider = "homebrew-cask";
            name = "stablyai/orca/orca";
          };
        };
        raycast = {
          pkg = pkgs.raycast;
          category = "desktop";
          support = {
            windows = {
              unsupported = "Managed only on macOS in this dotfiles profile";
            };
            darwin = {
              provider = "nix";
              source = "nixpkgs";
              nixAttr = "raycast";
              identity = {
                homepage = "https://raycast.com/";
                appName = "Raycast.app";
                bundleId = "com.raycast.macos";
                executable = "Raycast";
              };
            };
            linux = {
              unsupported = "Vendor does not publish a Linux build";
            };
          };
          legacyDarwin = {
            provider = "homebrew-cask";
            name = "raycast";
          };
        };
        # ── system capabilities ───────────────────────────────
        tart = {
          pkg = pkgs.tart;
          category = "system";
          support = {
            windows = {
              unsupported = "Tart requires Apple Silicon macOS";
            };
            darwin = {
              provider = "nix";
              source = "nixpkgs";
              nixAttr = "tart";
              identity = {
                homepage = "https://tart.run/";
                command = "tart";
                versionArgs = [ "--version" ];
              };
            };
            linux = {
              unsupported = "Tart requires Apple Silicon macOS";
            };
          };
          legacyDarwin = {
            provider = "homebrew-formula";
            name = "openai/tools/tart";
          };
        };
        docker-desktop = {
          pkg = dockerDesktopPackage;
          winget = "Docker.DockerDesktop";
          category = "system";
          installFeature = "WithDocker";
          support = {
            windows = {
              provider = "winget";
              source = "winget";
              identity = "Docker.DockerDesktop";
            };
            darwin = {
              provider = "nix";
              source = (darwinProviderCandidate "docker-desktop").source;
              identity = {
                homepage = "https://www.docker.com/products/docker-desktop/";
                appName = "Docker.app";
                bundleId = "com.docker.docker";
                executable = "com.docker.backend";
              };
            }
            // lib.optionalAttrs ((darwinProviderCandidate "docker-desktop").nixAttr != null) {
              nixAttr = (darwinProviderCandidate "docker-desktop").nixAttr;
            };
            linux = {
              provider = "system-manager";
              source = "nixpkgs";
              identity = "docker";
              nixAttr = "docker";
              systemModule = "docker";
            };
          };
          legacyDarwin = {
            provider = "homebrew-cask";
            name = "docker-desktop";
          };
        };
        hermes-desktop = {
          pkg = if pkgs.stdenv.hostPlatform.isDarwin then hermesDesktopPackage else null;
          winget = null;
          category = "terminal";
          installFeature = "WithHermes";
          support = {
            darwin = {
              provider = "nix";
              source = "hermes-agent";
              identity = {
                command = "hermes-desktop";
                versionArgs = [ "--version" ];
              };
            };
            linux = {
              unsupported = "Hermes Desktop is provisioned by the native macOS profile";
            };
            windows = {
              unsupported = "Hermes Desktop is provisioned by the native macOS profile";
            };
          };
        };
        hermes-desktop-docker = {
          pkg =
            if pkgs.stdenv.hostPlatform.isDarwin then
              pkgs.writeShellApplication {
                name = "hermes-desktop-docker";
                runtimeInputs = [
                  pkgs.curl
                  pkgs.jq
                ];
                text = builtins.readFile ../../scripts/sh/hermes-desktop-docker.sh;
              }
            else
              null;
          winget = null;
          category = "terminal";
          installFeature = "WithHermes";
          support = {
            darwin = {
              provider = "nix";
              source = "dotfiles";
              identity.command = "hermes-desktop-docker";
            };
            linux = {
              unsupported = "Hermes Desktop Docker launcher is provisioned by the native macOS profile";
            };
            windows = {
              unsupported = "Hermes Desktop Docker launcher is provisioned by the native macOS profile";
            };
          };
        };
        hermes-docker = {
          pkg =
            if pkgs.stdenv.hostPlatform.isDarwin then
              pkgs.writeShellApplication {
                name = "hermes-docker";
                runtimeInputs = [ dockerDesktopPackage ];
                text = ''
                  export HERMES_DOCKER_COMPOSE_PLUGIN="${dockerDesktopPackage}/libexec/docker/cli-plugins/docker-compose"
                  ${builtins.readFile ../../scripts/sh/hermes-docker.sh}
                '';
              }
            else
              null;
          winget = null;
          category = "terminal";
          installFeature = "WithHermes";
          support = {
            darwin = {
              provider = "nix";
              source = "dotfiles";
              identity.command = "hermes-docker";
            };
            linux = {
              unsupported = "Hermes Docker CLI is provisioned by the native macOS profile";
            };
            windows = {
              unsupported = "Hermes Docker CLI is provisioned by the native macOS profile";
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
          {
            provider = "winget";
            source = "winget";
            identity = entry.winget;
          }
        else if (entry.msstore or null) != null then
          {
            provider = "msstore";
            source = "msstore";
            identity = entry.msstore;
          }
        else if (entry.npm or null) != null then
          {
            provider = "npm";
            source = "npm";
            identity = entry.npm;
          }
        else
          let
            reason = unsupported "windows";
          in
          if reason == null then { } else { unsupported = reason; };
      darwin =
        if supports package "aarch64-darwin" || supports package "x86_64-darwin" then
          {
            provider = "nix";
            source = "nixpkgs";
            identity = name;
            nixAttr = name;
          }
        else
          let
            reason = unsupported "darwin";
          in
          if reason == null then { } else { unsupported = reason; };
      linux =
        if supports package "x86_64-linux" || supports package "aarch64-linux" then
          {
            provider = "nix";
            source = "nixpkgs";
            identity = name;
            nixAttr = name;
          }
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

  catalog = lib.mapAttrs (
    name: entry:
    entry
    // {
      support = defaultSupport name entry // (entry.support or { });
    }
  ) rawCatalog;

  mkWindowsOnlySupport = provider: identity: reason: {
    windows = {
      inherit provider identity;
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
    "GitHub.Copilot" = mkWindowsOnlySupport "winget" "GitHub.Copilot" "Windows application package";
    "Microsoft.PowerToys" =
      mkWindowsOnlySupport "winget" "Microsoft.PowerToys"
        "Windows system utility";
    "Microsoft.VCRedist.2015+.x64" =
      mkWindowsOnlySupport "winget" "Microsoft.VCRedist.2015+.x64"
        "Windows runtime component";
    "Microsoft.VisualStudio.2022.BuildTools" =
      mkWindowsOnlySupport "winget" "Microsoft.VisualStudio.2022.BuildTools"
        "Windows compiler toolchain";
    "Microsoft.WindowsTerminal" =
      mkWindowsOnlySupport "winget" "Microsoft.WindowsTerminal"
        "Windows shell host";
    "Microsoft.WSL" = mkWindowsOnlySupport "winget" "Microsoft.WSL" "Windows subsystem component";
    "9PLM9XGG6VKS" = mkWindowsOnlySupport "msstore" "9PLM9XGG6VKS" "Windows Store desktop application";
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

  isDarwinGuiNixPackage =
    entry:
    let
      darwinSupport = entry.support.darwin or { };
      identity = darwinSupport.identity or null;
    in
    (darwinSupport.provider or null) == "nix" && builtins.isAttrs identity && identity ? appName;

  # Resolve catalog IDs to Nix derivations selected for the current platform.
  resolveForInstallFeaturesWhere =
    enabledFeatures: predicate: names:
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
          && predicate entry
          && package != null
          && supports package pkgs.stdenv.hostPlatform.system
        then
          package
        else
          null
      ) names
    );

  resolveForInstallFeatures =
    enabledFeatures: resolveForInstallFeaturesWhere enabledFeatures (_: true);

  # Default package outputs contain only packages without an opt-in feature.
  # Feature profiles use allForInstallFeatures or the platform-specific
  # resolvers below with an explicit feature list.
  resolve = resolveForInstallFeatures [ ];

  darwinSystemPackagesForInstallFeatures =
    enabledFeatures:
    if pkgs.stdenv.hostPlatform.isDarwin then
      resolveForInstallFeaturesWhere enabledFeatures isDarwinGuiNixPackage (lib.attrNames catalog)
    else
      [ ];

  darwinHomePackagesForInstallFeatures =
    enabledFeatures:
    if pkgs.stdenv.hostPlatform.isDarwin then
      resolveForInstallFeaturesWhere enabledFeatures (entry: !isDarwinGuiNixPackage entry) (
        lib.attrNames catalog
      )
    else
      [ ];

  # Extract winget mappings (non-null only)
  wingetMap = lib.filterAttrs (_: v: v != null) (lib.mapAttrs (_: v: v.winget or null) catalog);
  wingetFeatureMap = lib.filterAttrs (_: v: v != null) (
    lib.mapAttrs (_: v: v.installFeature or null) catalog
  );
  msstoreMap = lib.filterAttrs (_: v: v != null) (lib.mapAttrs (_: v: v.msstore or null) catalog);
  npmMap = lib.filterAttrs (_: v: v != null) (lib.mapAttrs (_: v: v.npm or null) catalog);

  supportReport =
    lib.mapAttrs (
      _: entry:
      entry.support
      // {
        installFeature = entry.installFeature or null;
        legacyDarwin = entry.legacyDarwin or null;
      }
    ) catalog
    // lib.mapAttrs (
      _: support:
      support
      // {
        installFeature = null;
        legacyDarwin = null;
      }
    ) windowsOnlySupport;
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
        (entry.pkg or null) != null && supports entry.pkg pkgs.stdenv.hostPlatform.system
      else
        builtins.elem provider [
          "homebrew-cask"
          "homebrew-formula"
        ]
    ) catalog
  );

  hasValue = value: value != null && value != "";
  providerAllowedFields =
    provider:
    if provider == null then
      [ "unsupported" ]
    else if provider == "nix" then
      [
        "provider"
        "source"
        "identity"
        "nixAttr"
        "appName"
        "bundleId"
        "executable"
        "command"
        "versionArgs"
      ]
    else if provider == "homebrew-cask" then
      [
        "provider"
        "source"
        "identity"
        "cask"
      ]
    else if provider == "homebrew-formula" then
      [
        "provider"
        "source"
        "identity"
        "formula"
      ]
    else if
      builtins.elem provider [
        "winget"
        "msstore"
        "npm"
      ]
    then
      [
        "provider"
        "source"
        "identity"
      ]
    else if provider == "system-manager" then
      [
        "provider"
        "source"
        "identity"
        "nixAttr"
        "systemModule"
      ]
    else
      [
        "provider"
        "source"
        "identity"
      ];

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
          activePlatform = platform == platformKey;
          extraFields = builtins.filter (field: !(builtins.elem field (providerAllowedFields provider))) (
            builtins.attrNames platformData
          );
          providerSpecificErrors =
            lib.optional (
              provider == "homebrew-cask" && !hasValue (platformData.cask or null)
            ) "${prefix}homebrew-cask provider requires cask"
            ++ lib.optional (
              provider == "homebrew-formula" && !hasValue (platformData.formula or null)
            ) "${prefix}homebrew-formula provider requires formula"
            ++ lib.optional (
              provider == "system-manager" && !hasValue (platformData.systemModule or null)
            ) "${prefix}system-manager provider requires systemModule";
        in
        lib.optional (
          provider == null && (unsupported == null || unsupported == "")
        ) "${prefix}missing provider or reviewed unsupported reason"
        ++ lib.optional (
          provider != null && unsupported != null
        ) "${prefix}provider and unsupported cannot coexist"
        ++ lib.optional (
          provider != null && !hasValue (platformData.source or null)
        ) "${prefix}provider requires source"
        ++ lib.optional (
          provider != null && !hasValue (platformData.identity or null)
        ) "${prefix}provider requires identity"
        ++ lib.optional (
          (platformData.source or null) == "nixpkgs" && !hasValue (platformData.nixAttr or null)
        ) "${prefix}source = nixpkgs requires nixAttr"
        ++ lib.optional (
          provider == "nix" && activePlatform && (package == null || !lib.isDerivation package)
        ) "${prefix}nix provider requires a derivation"
        ++ lib.optional (
          provider == "nix"
          && activePlatform
          && package != null
          && lib.isDerivation package
          && !supports package pkgs.stdenv.hostPlatform.system
        ) "${prefix}nix provider derivation does not support ${platform}"
        ++ map (
          field:
          if provider == null then
            "${prefix}providerless metadata cannot include ${field}"
          else
            "${prefix}${provider} provider cannot include ${field}"
        ) extraFields
        ++ lib.optional (
          provider == "nix" && ((platformData.cask or null) != null || (platformData.formula or null) != null)
        ) "${prefix}catalog ID appears in both Nix and Homebrew resolution"
        ++ providerSpecificErrors
      )
      [
        "windows"
        "darwin"
        "linux"
      ];

  providerErrors = lib.concatMap (name: providerErrorsFor name supportReport.${name}) (
    lib.attrNames supportReport
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
  all = resolveForInstallFeatures null (lib.attrNames catalog);
  allForInstallFeatures =
    enabledFeatures: resolveForInstallFeatures enabledFeatures (lib.attrNames catalog);
  allWithout =
    excludedNames:
    resolveForInstallFeatures null (
      builtins.filter (name: !(builtins.elem name excludedNames)) (lib.attrNames catalog)
    );
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
    darwinDiscordPackage
    darwinSystemPackagesForInstallFeatures
    darwinHomePackagesForInstallFeatures
    darwinCasks
    darwinCasksForInstallFeatures
    darwinBrews
    darwinPackages
    selectDarwinPackage
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
