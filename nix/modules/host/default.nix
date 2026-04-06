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

      # CLI tools are managed by Home Manager (nix/home/packages.nix).
      # Only system-level packages that require root or NixOS module
      # integration belong here.
      environment.systemPackages = with pkgs; [
        git # needed by system-level operations (nix flake, etc.)
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

      # docker グループを作成する（Docker Desktop の bind mount が /var/run/docker.sock を
      # docker グループ所有で作成するため、nixos ユーザーが接続できるように）
      users.groups.docker = { };
      users.users.nixos.extraGroups = [ "docker" ];
    })
  ];
}
