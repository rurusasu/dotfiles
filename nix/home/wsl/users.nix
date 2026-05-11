# User → Home Manager module mapping for WSL host.
# Imported by nix/flakes/lib/hosts.nix as home-manager.users.
{
  nixos =
    { pkgs, ... }:
    let
      # GCM のパスには空白 (`Program Files`) が含まれるため、git が helper 値を
      # `sh -c` に渡す前にトークン分割しないようリテラルなダブルクォートで包む。
      # home-manager の INI 出力は埋め込み `"` を `\"` にエスケープし、git は
      # 読み出し時に外側のクォートを除去するので、最終的に shell に届くのは
      # 1 トークンのクォート付きパスになる。
      gcmHelper = ''"/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe"'';
    in
    {
      imports = [ ../common.nix ];

      # WSL: GitHub への HTTPS push は Windows 側の Git Credential Manager に委譲する。
      # WSL 内で credential.helper が未設定だと、git の認証フェーズで stdin 入力待ちと
      # なり非対話シェル経由 (`task push` 等) では無進捗でブロックする
      # （chezmoi が WSL 内まで適用されないためここで宣言的に補う）。
      # GCM 本体のパスは WSL 限定なので home-manager の WSL プロファイルに置く。
      # Exclude WSL mount paths from zoxide's database to avoid indexing
      # temporary runtime files under /mnt/wsl/ and /mnt/wslg/.
      home.sessionVariables._ZO_EXCLUDE_DIRS = "/mnt/wsl/*:/mnt/wslg/*";

      programs.zsh.shellAliases = {
        # nixpkgs installs Warp CLI as "warp-terminal"; alias to match Windows naming.
        # LD_LIBRARY_PATH must include wayland because Warp dlopen()s libwayland-client
        # at runtime and the binary bypasses nix-ld (it links directly against NixOS glibc).
        warp = "LD_LIBRARY_PATH=${pkgs.wayland}/lib:\${LD_LIBRARY_PATH:-} MESA_D3D12_DEFAULT_ADAPTER_NAME=Microsoft GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx warp-terminal";
        # NixOS rebuild shortcuts
        nrs = "sudo nixos-rebuild switch --flake ~/.dotfiles --impure && nix profile upgrade '.*' || nix profile install ~/.dotfiles#default";
        nrt = "sudo nixos-rebuild test --flake ~/.dotfiles --impure";
        nrb = "sudo nixos-rebuild boot --flake ~/.dotfiles --impure";
      };

      # fcitx5 user systemd service (X11 mode only).
      # WSLg's Wayland compositor does not support zwp_input_method_v2, so
      # WAYLAND_DISPLAY is explicitly unset to force X11/XWayland mode where
      # fcitx5's GTK_IM_MODULE bridge works.
      systemd.user.services.fcitx5 = {
        Unit = {
          Description = "Fcitx5 input method daemon (X11 mode)";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "/run/current-system/sw/bin/fcitx5 --disable=wayland";
          Restart = "on-failure";
          Environment = [
            "DISPLAY=:0"
            "WAYLAND_DISPLAY="
          ];
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      # gnome-keyring as a user systemd service.
      # WSL has no PAM login flow so the system-level keyring service is never
      # auto-started. This user unit ensures the daemon runs on every login.
      # The keyring starts locked; Warp will create a new default collection
      # with an empty password on first use, which is acceptable for WSL.
      systemd.user.services.gnome-keyring = {
        Unit = {
          Description = "GNOME Keyring daemon";
          After = [ "basic.target" ];
        };
        Service = {
          ExecStart = "${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --foreground --components=secrets";
          Restart = "on-abort";
        };
        Install.WantedBy = [ "default.target" ];
      };

      programs.git = {
        enable = true;
        settings = {
          credential."https://github.com".helper = gcmHelper;
          credential."https://gist.github.com".helper = gcmHelper;
        };
      };
    };
}
