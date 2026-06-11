# User → Home Manager module mapping for WSL host.
# Imported by nix/flakes/lib/hosts.nix as home-manager.users.
{
  nixos =
    { pkgs, ... }:
    {
      imports = [ ../common.nix ];

      # Exclude WSL mount paths from zoxide's database to avoid indexing
      # temporary runtime files under /mnt/wsl/ and /mnt/wslg/.

      # Declaratively manage fcitx5 input method profile.
      # fcitx5 overwrites this file on exit, so home-manager re-applies it on
      # each activation (nrs). force = true is required to overwrite the file
      # even when fcitx5 has already written its own copy.
      home.file.".config/fcitx5/profile" = {
        force = true;
        text = ''
          [Groups/0]
          Name=Default
          Default Layout=us
          DefaultIM=mozc

          [Groups/0/Items/0]
          Name=keyboard-us
          Layout=

          [Groups/0/Items/1]
          Name=mozc
          Layout=

          [GroupOrder]
          0=Default
        '';
      };

      home.sessionVariables = {
        _ZO_EXCLUDE_DIRS = "/mnt/wsl/*:/mnt/wslg/*";
        BROWSER = "explorer.exe";
        # fcitx5 GTK_IM_MODULE bridge: Warp runs in Wayland mode but reads these
        # env vars to delegate key events to the fcitx5 daemon via the GTK IM module.
        GTK_IM_MODULE = "fcitx";
        QT_IM_MODULE = "fcitx";
        XMODIFIERS = "@im=fcitx";
        # 1Password multi-account: chezmoi's [onepassword].command routes to
        # op.exe under WSL (LIF-182), but Windows binaries inherit env vars
        # from WSL only when WSLENV lists them. /u makes OP_ACCOUNT visible
        # only when crossing WSL→Windows (not the other direction).
        # Without this, op.exe fails with "multiple accounts found" because
        # chezmoi templates call op signin without --account.
        WSLENV = "OP_ACCOUNT/u";
        OP_ACCOUNT = "EJLA3HRAVZBCXIQ7SRSFGQBTNU";
      };

      programs.zsh.shellAliases = {
        # nixpkgs installs Warp CLI as "warp-terminal"; alias to match Windows naming.
        # LD_LIBRARY_PATH must include wayland because Warp dlopen()s libwayland-client
        # at runtime and the binary bypasses nix-ld (it links directly against NixOS glibc).
        warp = "LD_LIBRARY_PATH=${pkgs.wayland}/lib:\${LD_LIBRARY_PATH:-} MESA_D3D12_DEFAULT_ADAPTER_NAME=Microsoft warp-terminal";
        # NixOS rebuild shortcuts
        nrs = "nix flake update --flake ~/.dotfiles && sudo nixos-rebuild switch --flake ~/.dotfiles --impure && nix profile upgrade '.*' || nix profile install ~/.dotfiles#default";
        nrt = "sudo nixos-rebuild test --flake ~/.dotfiles --impure";
        nrb = "sudo nixos-rebuild boot --flake ~/.dotfiles --impure";
      };

      # fcitx5 user systemd service.
      # WSLg's Wayland compositor does not support zwp_input_method_v2, so
      # fcitx5 is started with --disable=wayland to prevent it from crashing
      # ("waylandmodule: Connection removed"). Warp itself continues to run in
      # Wayland mode; Japanese input works via the GTK_IM_MODULE=fcitx bridge
      # which routes key events to this daemon regardless of display backend.
      systemd.user.services.fcitx5 = {
        Unit = {
          Description = "Fcitx5 input method daemon";
          After = [ "basic.target" ];
        };
        Service = {
          ExecStart = "/run/current-system/sw/bin/fcitx5 --disable=wayland";
          Restart = "on-failure";
          Environment = [
            "DISPLAY=:0"
            "WAYLAND_DISPLAY="
            # fcitx5 searches its own store-path lib dir by default, not the merged
            # /run/current-system/sw path. This makes addon .so files from separate
            # packages (e.g. fcitx5-mozc) visible at runtime.
            "FCITX_ADDON_DIRS=/run/current-system/sw/lib/fcitx5"
          ];
        };
        Install.WantedBy = [ "default.target" ];
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

    };
}
