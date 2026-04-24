# Single Source of Truth for all packages across platforms.
# Each entry defines: nix derivation, winget ID (null if none), category.
#
# Imported by:
#   - nix/flakes/packages.nix → perSystem buildEnv outputs
#   - nix/home/packages.nix   → home.packages
#   - nix/packages/winget.nix → winget/pnpm JSON generation
{ pkgs, lib }:
let
  catalog = {
    # ── core ──────────────────────────────────────────────
    chezmoi   = { pkg = pkgs.chezmoi;   winget = "twpayne.chezmoi";         category = "core"; };
    git       = { pkg = pkgs.git;       winget = "Git.Git";                 category = "core"; };
    gh        = { pkg = pkgs.gh;        winget = "GitHub.cli";              category = "core"; };
    fd        = { pkg = pkgs.fd;        winget = "sharkdp.fd";              category = "core"; };
    ripgrep   = { pkg = pkgs.ripgrep;   winget = "BurntSushi.ripgrep.MSVC"; category = "core"; };
    bat       = { pkg = pkgs.bat;       winget = null;                      category = "core"; };
    eza       = { pkg = pkgs.eza;       winget = "eza-community.eza";       category = "core"; };
    zoxide    = { pkg = pkgs.zoxide;    winget = "ajeetdsouza.zoxide";      category = "core"; };
    fzf       = { pkg = pkgs.fzf;       winget = "junegunn.fzf";            category = "core"; };
    unzip     = { pkg = pkgs.unzip;     winget = null;                      category = "core"; };
    p7zip     = { pkg = pkgs.p7zip;     winget = null;                      category = "core"; };

    # ── dev ───────────────────────────────────────────────
    nodejs_22 = { pkg = pkgs.nodejs_22; winget = "OpenJS.NodeJS.LTS";       category = "dev"; };
    python3   = { pkg = pkgs.python3;   winget = null;                      category = "dev"; };
    go        = { pkg = pkgs.go;        winget = null;                      category = "dev"; };
    rustup    = { pkg = pkgs.rustup;    winget = "Rustlang.Rustup";         category = "dev"; };
    gnumake   = { pkg = pkgs.gnumake;   winget = null;                      category = "dev"; };
    cmake     = { pkg = pkgs.cmake;     winget = null;                      category = "dev"; };
    ghq       = { pkg = pkgs.ghq;       winget = null;                      category = "dev"; };
    uv        = { pkg = pkgs.uv;        winget = "astral-sh.uv";           category = "dev"; };
    pnpm      = { pkg = pkgs.pnpm;      winget = null;                      category = "dev"; };

    # ── terminal ──────────────────────────────────────────
    wezterm   = { pkg = pkgs.wezterm;   winget = "wez.wezterm";             category = "terminal"; };
    tmux      = { pkg = pkgs.tmux;      winget = null;                      category = "terminal"; };
    starship  = { pkg = pkgs.starship;  winget = "Starship.Starship";       category = "terminal"; };

    # ── editors ───────────────────────────────────────────
    neovim    = { pkg = pkgs.neovim;    winget = "Neovim.Neovim";           category = "editors"; };
    obsidian  = { pkg = pkgs.obsidian;  winget = "Obsidian.Obsidian";       category = "editors"; };

    # ── llm ───────────────────────────────────────────────
    claude-code = { pkg = pkgs.claude-code; winget = null;                  category = "llm"; };
    codex       = { pkg = pkgs.codex;       winget = null;                  category = "llm"; };

    # ── communication ─────────────────────────────────────
    slack     = { pkg = pkgs.slack;     winget = "SlackTechnologies.Slack";  category = "communication"; };

    # ── k8s ───────────────────────────────────────────────
    kind            = { pkg = pkgs.kind;            winget = null;          category = "k8s"; };
    kubectl         = { pkg = pkgs.kubectl;         winget = null;          category = "k8s"; };
    kubernetes-helm = { pkg = pkgs.kubernetes-helm; winget = null;          category = "k8s"; };
    k9s             = { pkg = pkgs.k9s;             winget = null;          category = "k8s"; };
    kubectx         = { pkg = pkgs.kubectx;         winget = null;          category = "k8s"; };

    # ── infra ─────────────────────────────────────────────
    go-task        = { pkg = pkgs.go-task;        winget = "Task.Task";               category = "infra"; };
    treefmt        = { pkg = pkgs.treefmt;        winget = null;                      category = "infra"; };
    pre-commit     = { pkg = pkgs.pre-commit;     winget = null;                      category = "infra"; };
    powershell     = { pkg = pkgs.powershell;     winget = "Microsoft.PowerShell";    category = "infra"; };
    _1password-cli = { pkg = pkgs._1password-cli; winget = "AgileBits.1Password.CLI"; category = "infra"; };
    opencode       = { pkg = pkgs.opencode;       winget = "SST.opencode";            category = "infra"; };
  };

  # Group package names by category
  grouped = lib.groupBy (name: catalog.${name}.category) (lib.attrNames catalog);

  # Resolve attr names to derivations
  resolve = names: map (n: catalog.${n}.pkg) names;

  # Extract winget mappings (non-null only)
  wingetMap = lib.filterAttrs (_: v: v != null)
    (lib.mapAttrs (_: v: v.winget) catalog);

in
# Category-resolved package lists (auto-derived from catalog)
lib.mapAttrs (_: names: resolve names) grouped
//
{
  # All packages (flat list)
  all = resolve (lib.attrNames catalog);

  # Windows: nix attr name → winget PackageIdentifier
  inherit wingetMap;

  # Cross-platform pnpm global packages
  pnpmGlobal = [
    "@tobilu/qmd"
  ];

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
    ];
    msstore = [
      "9NT1R1C2HH7J"
    ];
    pnpm = [
      "@anthropic-ai/claude-code"
      "@google/gemini-cli"
    ];
  };
}
