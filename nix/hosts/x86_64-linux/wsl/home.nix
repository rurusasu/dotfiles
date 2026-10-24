{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  inherit ((import ../../../modules/fonts.nix { inherit pkgs; })) fonts;
  japaneseFonts = import ../../../modules/fonts/japanese.nix { inherit lib pkgs; };
  chrome = import ../../../modules/browsers/chrome { inherit pkgs; };
in
{
  imports = [
    (import ../../../modules/desktop.nix).wslDesktop
    (import ../../../modules/tools.nix).chatgptCli
    ../../../modules/editors/nvim
    ../../../home/common.nix
    ../../../home/keybindings/windows-export.nix
  ];

  dotfiles = {
    keybindings.fromWindowsExport = true;
    starship.osSymbol = "❄️ ";
    # Relative links must stay on the same Windows drive to work from both OSes.
    gwq.settings.worktree.basedir = "/mnt/d/worktrees";
  };

  programs = {
    git = {
      signing.signer = "${config.home.homeDirectory}/.local/bin/op-ssh-sign-wsl";
      settings.ghq.root = [ "/mnt/d" ];
    };

    # Use the native Windows helper only for repositories on Windows drives.
    # Starship retains its Linux implementation for the WSL filesystem.
    starship.settings.git_status.windows_starship = "starship.exe";

    zsh = {
      initContent = lib.mkBefore ''
        # Coalesce automatic suggestions while typing; explicit Tab keeps its defaults.
        zstyle ':autocomplete:' delay 0.15
        zstyle ':autocomplete:list-choices:' min-input 2
      '';
      shellAliases = {
        # NixOS rebuild shortcuts
        nrs = "task --dir ~/.dotfiles nrs";
        nrt = "sudo nixos-rebuild test --flake ~/.dotfiles --impure";
        nrb = "sudo nixos-rebuild boot --flake ~/.dotfiles --impure";
      };
    };
  };

  # Windows cannot follow Home Manager's absolute symlink over the WSL share.
  # Export its generated store file so the helper reads the same configuration.
  home.sessionVariables.STARSHIP_CONFIG = lib.mkForce (
    toString config.home.file.${config.programs.starship.configPath}.source
  );

  # Missing/partial commands otherwise trigger synchronous Windows PATH scans.
  xdg.configFile."zsh-patina/config.toml".text = ''
    [highlighting]
    dynamic = { callables = false, paths = "complete" }
  '';

  fonts.fontconfig = lib.mkMerge [
    fonts.fontconfig
    japaneseFonts.fontconfig
  ];
  home = {
    homeDirectory = lib.mkDefault "/home/${config.home.username}";
    packages = fonts.packages ++ japaneseFonts.packages;

    file = {
      ".local/bin/op-ssh-sign-wsl" = {
        source = ./op-ssh-sign-wsl;
        executable = true;
        force = true;
      };

      # Declaratively manage fcitx5 input method profile.
      # fcitx5 overwrites this file on exit, so home-manager re-applies it on
      # each activation (nrs). force = true is required to overwrite the file
      # even when fcitx5 has already written its own copy.
      ".config/fcitx5/profile" = {
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
    };

    sessionVariables = {
      # Windows cannot follow Home Manager's absolute symlink over the WSL share.
      # Export its generated store file so the helper reads the same configuration.
      STARSHIP_CONFIG = lib.mkForce (
        toString config.home.file.${config.programs.starship.configPath}.source
      );
      # Avoid recording temporary runtime directories in zoxide's database.
      _ZO_EXCLUDE_DIRS = "/mnt/wsl/*:/mnt/wslg/*";
      BROWSER = "${chrome}/bin/google-chrome-stable";
      # fcitx5 GTK_IM_MODULE bridge for WSLg GUI applications.
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
  };

  # fcitx5 user systemd service.
  # WSLg's Wayland compositor does not support zwp_input_method_v2, so
  # fcitx5 is started with --disable=wayland to prevent it from crashing
  # ("waylandmodule: Connection removed"). GTK applications can still route
  # key events to this daemon through GTK_IM_MODULE=fcitx.
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
  # The keyring starts locked; GUI apps can create a default collection on
  # first use, which is acceptable for WSL.
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
}
