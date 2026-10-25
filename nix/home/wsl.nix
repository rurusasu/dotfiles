{
  config,
  inputs,
  pkgs,
  lib,
  ...
}:
let
  graphicsEnvironment = {
    # Mesa dynamically loads the Windows bridge libraries from this directory.
    LD_LIBRARY_PATH = "/run/opengl-driver/lib";
    # https://github.com/microsoft/wslg/issues/1332
    GALLIUM_DRIVER = "d3d12";
    WARP_ENABLE_WAYLAND = "1";
  };
in
{
  imports = [
    inputs.nixos-vscode-server.homeModules.default
    (import ../modules/tools.nix).wslDesktop
    (import ../modules/tools.nix).chatgptCli
    ../modules/fonts/japanese.nix
    ./common.nix
    ./keybindings/windows-export.nix
  ];

  dotfiles = {
    keybindings.fromWindowsExport = true;
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

  # Missing/partial commands otherwise trigger synchronous Windows PATH scans.
  xdg.configFile = {
    "zsh-patina/config.toml".text = ''
      [highlighting]
      dynamic = { callables = false, paths = "complete" }
    '';

    # Link only the declared files so fcitx5 can keep its writable user data.
    # It replaces profile on exit; restore the declared profile on activation.
    fcitx5 = {
      recursive = true;
      force = true;
    };

    # The standard package also supplies XDG Autostart. The systemd unit below
    # owns startup because WSLg needs its Wayland frontend disabled.
    "autostart/org.fcitx.Fcitx5.desktop".text = ''
      [Desktop Entry]
      Hidden=true
    '';
  };

  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      addons = [ pkgs.fcitx5-mozc ];
      waylandFrontend = false;
      settings.inputMethod = {
        "Groups/0" = {
          Name = "Default";
          "Default Layout" = "us";
          DefaultIM = "mozc";
        };
        "Groups/0/Items/0" = {
          Name = "keyboard-us";
          Layout = "";
        };
        "Groups/0/Items/1" = {
          Name = "mozc";
          Layout = "";
        };
        GroupOrder."0" = "Default";
      };
    };
  };

  home = {
    homeDirectory = lib.mkDefault "/home/${config.home.username}";
    file = {
      ".local/bin/op" = {
        executable = true;
        text = ''
          #!${pkgs.runtimeShell}
          # Linux processes need native secret injection; never re-enter this wrapper.
          if [ "''${1:-}" = "run" ]; then
            exec ${pkgs._1password-cli}/bin/op "$@"
          fi

          # Windows op.exe authenticates through the desktop app's named pipe.
          OP_EXE=$(command -v op.exe) || {
            echo "[ERROR] op.exe not found in PATH" >&2
            exit 1
          }
          OP_VARS=$(${pkgs.coreutils}/bin/env | ${pkgs.gnugrep}/bin/grep ^OP_ | ${pkgs.coreutils}/bin/cut -d= -f1 | ${pkgs.coreutils}/bin/tr '\n' ':')
          export WSLENV="''${WSLENV:-}:''${OP_VARS%:}"
          exec "$OP_EXE" "$@"
        '';
      };
      ".local/bin/op-ssh-sign-wsl" = {
        source = ./op-ssh-sign-wsl;
        executable = true;
        force = true;
      };
    };

    sessionVariables = graphicsEnvironment // {
      # Windows cannot follow Home Manager's absolute symlink over the WSL share.
      # Export its generated store file so the helper reads the same configuration.
      STARSHIP_CONFIG = lib.mkForce (
        toString config.home.file.${config.programs.starship.configPath}.source
      );
      # Avoid recording temporary runtime directories in zoxide's database.
      _ZO_EXCLUDE_DIRS = "/mnt/wsl/*:/mnt/wslg/*";
      # 1Password multi-account: chezmoi's [onepassword].command routes to
      # op.exe under WSL (LIF-182), but Windows binaries inherit env vars
      # from WSL only when WSLENV lists them. /u makes OP_ACCOUNT visible
      # only when crossing WSL→Windows (not the other direction).
      # Without this, op.exe fails with "multiple accounts found" because
      # chezmoi templates call op signin without --account.
      WSLENV = "OP_ACCOUNT/u";
      OP_ACCOUNT = config.dotfiles.onePassword.account;
    };
  };

  services.vscode-server = {
    enable = true;
    installPath = [
      "$HOME/.vscode-server"
      "$HOME/.vscode-server-insiders"
    ];
  };

  # WSL has no PAM login flow so the system-level keyring service is never
  # auto-started. This user unit ensures the daemon runs on every login.
  # The keyring starts locked; GUI apps can create a default collection on
  # first use, which is acceptable for WSL.
  services.gnome-keyring = {
    enable = true;
    components = [ "secrets" ];
  };
  systemd.user = {
    # WSLg exports its displays to shells, but the user manager starts without
    # a desktop login and needs them for D-Bus-activated GTK portal backends.
    sessionVariables = graphicsEnvironment // {
      DISPLAY = ":0";
      WAYLAND_DISPLAY = "wayland-0";
    };

    # WSLg has no desktop session manager to activate this portal prerequisite.
    targets.graphical-session = {
      Unit = {
        Description = "Current graphical user session";
        Documentation = [ "man:systemd.special(7)" ];
        Requires = [ "basic.target" ];
        RefuseManualStart = true;
        StopWhenUnneeded = true;
      };
      Install.WantedBy = [ "default.target" ];
    };

    services = {
      # WSLg's Wayland compositor does not support zwp_input_method_v2, so
      # waylandFrontend = false supplies the IM environment but does not disable
      # the daemon's Wayland addon. Keep that WSLg-specific startup override.
      fcitx5-daemon = {
        Unit.After = [ "basic.target" ];
        Service = {
          ExecStart = lib.mkForce "${config.i18n.inputMethod.package}/bin/fcitx5 --disable=wayland";
          Restart = "on-failure";
          Environment = [
            "DISPLAY=:0"
            "WAYLAND_DISPLAY="
          ];
        };
        Install.WantedBy = lib.mkForce [ "default.target" ];
      };

      gnome-keyring = {
        Unit.After = [ "basic.target" ];
        Install.WantedBy = lib.mkForce [ "default.target" ];
      };
    };
  };
}
