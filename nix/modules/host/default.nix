{ lib, pkgs, config, ... }:
let
  inherit (lib) mkOption mkIf mkMerge types;
in
{
  options.mySettings.wsl.dockerDesktopIntegration = mkOption {
    type = types.bool;
    default = false;
    description = "Enable Docker Desktop WSL2 integration (required for kind to use Docker as container runtime)";
  };

  config = mkMerge [
    {
      nix = {
        settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          auto-optimise-store = true;
        };
        gc = {
          automatic = true;
          dates = "weekly";
          options = "--delete-older-than 7d";
        };
      };

      nixpkgs.config.allowUnfree = true;
      programs.zsh.enable = true;

      programs.git = {
        enable = true;
        config = {
          safe.directory = "*";
        };
      };

      environment.systemPackages = with pkgs; [
        # Dotfiles manager
        chezmoi

        # Version control
        git
        gh

        # Modern CLI replacements
        fd # find alternative
        ripgrep # grep alternative
        bat # cat alternative
        eza # ls alternative
        zoxide # cd alternative
        fzf # fuzzy finder

        # Shell prompt
        starship

        # Editor
        neovim

        # Task runner
        go-task

        # Archive tools
        unzip
        p7zip

        # Python toolchain
        uv

        # JavaScript runtime (for claude-code, gemini-cli, openclaw — pnpm via corepack)
        nodejs_22 # openclaw requires Node.js 22+

        # Secret management
        _1password-cli

        # Formatter & lint runner (for git pre-commit hooks)
        treefmt
        pre-commit
        powershell # provides pwsh for PowerShell test hook

        # AI coding agents
        opencode

        # Kubernetes tools (kind-based local cluster)
        kind # Local Kubernetes clusters using Docker
        kubectl # Kubernetes CLI
        kubernetes-helm # Kubernetes package manager
        k9s # Kubernetes TUI
        kubectx # Fast cluster switching
      ];
    }

    # Docker Desktop WSL integration: /mnt/wsl は noexec でマウントされるため
    # Docker Desktop のプロキシバイナリが実行できない。exec で再マウントする。
    # /mnt/wsl は Docker Desktop 接続時に非同期でマウントされるため、
    # path unit で監視し、mountpoint になった時点でサービスを起動する。
    (mkIf config.mySettings.wsl.dockerDesktopIntegration {
      # /proc/mounts の変更を監視し、/mnt/wsl がマウントされたタイミングでサービスを起動する。
      # PathIsMountPoint は path unit の有効なディレクティブではないため PathChanged を使用する。
      systemd.paths."docker-desktop-mnt-wsl-exec" = {
        description = "Watch /proc/mounts for Docker Desktop WSL integration";
        wantedBy = [ "multi-user.target" ];
        pathConfig.PathChanged = "/proc/mounts";
      };

      systemd.services."docker-desktop-mnt-wsl-exec" = {
        description = "Remount /mnt/wsl with exec for Docker Desktop WSL integration";
        # /mnt/wsl が未マウントのときはスキップする（/proc/mounts 変更の都度トリガーされるため）
        unitConfig.ConditionPathIsMountPoint = "/mnt/wsl";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.util-linux}/bin/mount -o remount,exec /mnt/wsl";
        };
      };
    })
  ];
}
