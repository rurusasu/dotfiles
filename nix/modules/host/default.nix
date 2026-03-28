{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib)
    mkOption
    mkIf
    mkMerge
    types
    ;
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
          # WSL の /mnt/ 配下は Windows 側の所有者 (UID 1000 等) と NixOS の UID が一致しないため
          # CVE-2022-24765 の ownership チェックを全ディレクトリに対して無効化している。
          # /mnt/ 以下に悪意のある .git/hooks が存在するリスクは許容する（個人端末のみ）。
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

        # JavaScript runtime (for claude-code, gemini-cli, openclaw)
        nodejs_22 # openclaw requires Node.js 22+
        pnpm # WSL interop 経由で Windows 版が見えるため Linux ネイティブ版を明示的に提供

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
    # /mnt/wsl は Docker Desktop 接続時に非同期でマウントされる。
    # procfs は inotify イベントを発行しないため path unit は使用できない。
    # timer で定期的にチェックし、mountpoint になったときだけ remount する。
    (mkIf config.mySettings.wsl.dockerDesktopIntegration {
      # Docker CLI（デーモンなし）- Docker Desktop のソケットに接続するため
      environment.systemPackages = with pkgs; [ docker-client ];

      systemd.timers."docker-desktop-mnt-wsl-exec" = {
        description = "Periodically remount /mnt/wsl with exec for Docker Desktop WSL integration";
        wantedBy = [ "multi-user.target" ];
        timerConfig = {
          OnBootSec = "10s";
          OnUnitActiveSec = "30s";
        };
      };

      systemd.services."docker-desktop-mnt-wsl-exec" = {
        description = "Remount /mnt/wsl with exec for Docker Desktop WSL integration";
        # /mnt/wsl が mountpoint でない場合はスキップ（timer が定期的にトリガーするため）
        unitConfig.ConditionPathIsMountPoint = "/mnt/wsl";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.util-linux}/bin/mount -o remount,exec /mnt/wsl";
        };
      };

      # Docker Desktop は NixOS の /var/run/docker.sock へ bind mount を試みるが、
      # systemd 管理の tmpfs のため失敗する。
      # 実ソケットは /mnt/wsl/docker-desktop-bind-mounts/NixOS/docker.sock に存在するので
      # シンボリックリンクで proxy が接続できるようにする。
      systemd.tmpfiles.rules = [
        "L+ /var/run/docker.sock - - - - /mnt/wsl/docker-desktop-bind-mounts/NixOS/docker.sock"
      ];
    })
  ];
}
