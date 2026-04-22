# Single Source of Truth for all packages across platforms.
#
# Imported by:
#   - nix/home/packages.nix   → home.packages (Linux/macOS)
#   - nix/packages/winget.nix → winget packages.json generation (Windows)
{ pkgs }:
let
  core = with pkgs; [
    chezmoi
    git
    gh
    fd
    ripgrep
    bat
    eza
    zoxide
    fzf
    unzip
    p7zip
  ];

  dev = with pkgs; [
    nodejs_22
    python3
    go
    rustup
    gnumake
    cmake
    ghq
    uv
    pnpm
  ];

  terminal = with pkgs; [
    wezterm
    tmux
    starship
  ];

  editors = with pkgs; [
    neovim
    obsidian
  ];

  llm = with pkgs; [
    claude-code
    codex
  ];

  communication = with pkgs; [
    slack
  ];

  k8s = with pkgs; [
    kind
    kubectl
    kubernetes-helm
    k9s
    kubectx
  ];

  infra = with pkgs; [
    go-task
    treefmt
    pre-commit
    powershell
    _1password-cli
    opencode
  ];
in
{
  # All packages for Home Manager (Linux/macOS)
  packages = core ++ dev ++ terminal ++ editors ++ llm ++ communication ++ k8s ++ infra;

  # Cross-platform pnpm global packages (no nix equivalent)
  pnpmGlobal = [
    "@tobilu/qmd"
  ];

  # nix attr name → winget PackageIdentifier
  # Only cross-platform tools that have a winget equivalent.
  wingetMap = {
    chezmoi = "twpayne.chezmoi";
    git = "Git.Git";
    gh = "GitHub.cli";
    fd = "sharkdp.fd";
    ripgrep = "BurntSushi.ripgrep.MSVC";
    eza = "eza-community.eza";
    zoxide = "ajeetdsouza.zoxide";
    fzf = "junegunn.fzf";
    starship = "Starship.Starship";
    neovim = "Neovim.Neovim";
    nodejs_22 = "OpenJS.NodeJS.LTS";
    rustup = "Rustlang.Rustup";
    uv = "astral-sh.uv";
    wezterm = "wez.wezterm";
    obsidian = "Obsidian.Obsidian";
    opencode = "SST.opencode";
    _1password-cli = "AgileBits.1Password.CLI";
    powershell = "Microsoft.PowerShell";
    slack = "SlackTechnologies.Slack";
    go-task = "Task.Task";
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
    ];
    msstore = [
      "9NT1R1C2HH7J"
    ];
    pnpm = [
      "@google/gemini-cli"
    ];
  };
}
