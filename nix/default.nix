# Consolidated host definitions, Home Manager defaults, and configuration registration.
{
  inputs ? { },
}:
let
  tools = import ./modules/tools.nix;
  # Standard NixOS/nix-darwin modules share daemon and Home Manager integration.
  systemDefaults =
    { inputs, pkgs, ... }:
    {
      nix = {
        package = pkgs.lixPackageSets.stable.lix;
        settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          extra-substituters = [ "https://cache.numtide.com" ];
          extra-trusted-public-keys = [
            "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
          ];
        };
        gc = {
          automatic = true;
          options = "--delete-old";
        };
      };
      nixpkgs.config.allowUnfree = true;
      programs.zsh = {
        enable = true;
        # zsh-autocomplete initializes completion.
        enableGlobalCompInit = false;
      };
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = { inherit inputs; };
      };
    };
  hostModules = {
    nixos =
      {
        config,
        inputs,
        lib,
        pkgs,
        ...
      }:
      let
        identity =
          if config.wsl.enable or false then
            {
              user = config.wsl.defaultUser;
              home = "/home/${config.wsl.defaultUser}";
              group = "users";
              uid = "";
              gid = "";
            }
          else
            # Native NixOS reuses the account invoking sudo.
            let
              sudoUser = builtins.getEnv "SUDO_USER";
              currentUser = builtins.getEnv "USER";
              user =
                if sudoUser != "" && sudoUser != "root" then
                  sudoUser
                else if builtins.pathExists /etc/NIXOS && currentUser != "" && currentUser != "root" then
                  currentUser
                else
                  "nixos";
              account = lib.findFirst (entry: builtins.length entry >= 7 && builtins.head entry == user) null (
                if builtins.pathExists /etc/passwd then
                  map (lib.splitString ":") (lib.splitString "\n" (builtins.readFile /etc/passwd))
                else
                  [ ]
              );
              gid = if account == null then "" else builtins.elemAt account 3;
              groupEntry =
                lib.findFirst (entry: builtins.length entry >= 3 && builtins.elemAt entry 2 == gid) null
                  (
                    if builtins.pathExists /etc/group then
                      map (lib.splitString ":") (lib.splitString "\n" (builtins.readFile /etc/group))
                    else
                      [ ]
                  );
            in
            {
              inherit user gid;
              home = if account == null then "/home/${user}" else builtins.elemAt account 5;
              uid = if account == null then "" else builtins.elemAt account 2;
              group = if groupEntry == null then "users" else builtins.head groupEntry;
            };
        uid = if identity.uid == "" then null else lib.toInt identity.uid;
        gid = if identity.gid == "" then null else lib.toInt identity.gid;
      in
      {
        imports = [
          systemDefaults
          ./modules/fonts.nix
          ./modules/docker.nix
          inputs.home-manager.nixosModules.home-manager
        ];

        nix.gc.dates = "weekly";
        fonts.fontDir.enable = true;
        system.stateVersion = "26.05";
        home-manager.users.${identity.user} =
          homeModules.${if config.wsl.enable or false then "wsl" else "linux"};

        users = {
          groups.${identity.group} = lib.optionalAttrs (gid != null) { inherit gid; };
          users.${identity.user} = {
            isNormalUser = true;
            # NixOS installs zsh before Home Manager activates the account.
            shell = pkgs.zsh;
            home = lib.mkDefault identity.home;
            linger = true;
            inherit (identity) group;
            extraGroups = [
              "wheel"
              "docker"
            ];
          }
          // lib.optionalAttrs (uid != null) { inherit uid; };
        };
      };
    linux = {
      imports = [ hostModules.nixos ];

      programs.hyprland.enable = true;
      home-manager.sharedModules = [ ./home/keybindings/hyprland.nix ];
    };
    wsl =
      {
        config,
        pkgs,
        ...
      }:
      let
        user = config.wsl.defaultUser;
        repository = "${config.users.users.${user}.home}/.dotfiles";
        fontDirectory = "/usr/local/share/fonts/dotfiles-wslg";
      in

      {
        imports = [ hostModules.nixos ];

        wsl = {
          enable = true;
          # Expose Windows D3D12/DXCore libraries through /run/opengl-driver/lib.
          useWindowsDriver = true;

          # WSL owns and protects its existing Windows executable registration.
          # Re-registering it makes systemd-binfmt fail on WSL's read-only status file.
          interop.register = false;

          # NixOS manages /etc/hosts through networking.extraHosts.
          wslConf.network.generateHosts = false;
        };

        # Chrome's process locale is Japanese; keep the system's default language.
        i18n.extraLocales = [ "ja_JP.UTF-8/UTF-8" ];

        # Root evaluates the Windows-mounted, user-owned checkout during rebuild.
        # Own its exact trust declaration here, never by editing Home Manager files.
        programs = {
          git = {
            enable = true;
            config.safe.directory = [ repository ];
          };
          # Home Manager's GTK font setting is read through the settings portal.
          dconf.enable = true;
          # Allow running dynamically linked binaries in WSL (e.g. VS Code Server).
          nix-ld = {
            enable = true;
            libraries = with pkgs; [
              wayland
              libxkbcommon
            ];
          };
        };
        assertions = [
          {
            assertion = builtins.substring 0 1 repository == "/" && !(pkgs.lib.hasInfix "*" repository);
            message = "WSL Git trust requires one absolute checkout path without wildcards.";
          }
        ];

        systemd.user = {
          # switch-to-configuration restarts this service for existing user managers.
          # A new WantedBy link alone would only take effect at the next login.
          services.nixos-activation = {
            wants = [ "graphical-session.target" ];
            after = [ "graphical-session.target" ];
          };
        };

        xdg.portal = {
          enable = true;
          extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
          config.common.default = "*";
        };

        environment = {
          etc = {
            # kind nodes mount /etc/containerd/certs.d and use the in-cluster Zot
            # as the mirror for registry.localhost.
            "containerd/certs.d/registry.localhost/hosts.toml".text = ''
              server = "http://registry.localhost"

              [host."http://zot.infra.svc.cluster.local:5080"]
                capabilities = ["pull", "resolve"]
            '';
          };
          systemPackages = with pkgs; [
            nvidia-container-toolkit
          ];
        };

        system.activationScripts = {
          # WSLg's compositor cannot resolve the user distro's absolute store links.
          # Preserve running applications and copy the real font files into /usr/local.
          wslgFonts = {
            deps = [ "specialfs" ];
            text = ''
              ${pkgs.coreutils}/bin/install -d -m 0755 ${fontDirectory}
              # Retire the Noto CJK file previously distributed by this module.
              ${pkgs.coreutils}/bin/rm -f -- ${fontDirectory}/NotoSansCJK-VF.otf.ttc
              ${pkgs.coreutils}/bin/install --compare -m 0644 ${pkgs.udev-gothic-nf}/share/fonts/truetype/UDEVGothicNF-Regular.ttf ${fontDirectory}/UDEVGothicNF-Regular.ttf
              ${pkgs.coreutils}/bin/install --compare -m 0644 ${pkgs.udev-gothic-nf}/share/fonts/truetype/UDEVGothicNF-Bold.ttf ${fontDirectory}/UDEVGothicNF-Bold.ttf
              ${pkgs.coreutils}/bin/install --compare -m 0644 ${pkgs.noto-fonts-color-emoji}/share/fonts/noto/NotoColorEmoji.ttf ${fontDirectory}/NotoColorEmoji.ttf
            '';
          };

          wslWhoami = {
            text = ''
              mkdir -p /usr/bin
              ln -sf /run/current-system/sw/bin/whoami /usr/bin/whoami
            '';
          };

          # Retire only the exact wrapper previously copied by this module. Keep
          # unrelated administrator files and symlinks at this path untouched.
          retireSystemOpWrapper = {
            text = ''
              if [ -f /usr/local/bin/op ] && [ ! -L /usr/local/bin/op ]; then
                # The bash store path can change independently of the wrapper body.
                if ${pkgs.coreutils}/bin/head -n 1 /usr/local/bin/op | \
                  ${pkgs.gnugrep}/bin/grep -Eq '^#!/nix/store/[a-z0-9]{32}-bash-[^/]+/bin/bash$' && \
                  ${pkgs.coreutils}/bin/tail -n +2 /usr/local/bin/op | \
                  ${pkgs.diffutils}/bin/cmp -s ${
                    pkgs.writeText "legacy-op-wrapper-body" (
                      ''
                        OP_NATIVE="/etc/profiles/per-user/${user}/bin/op"
                        # op run injects secrets into Linux processes — keep on native binary
                        if [ "$1" = "run" ] && [ -x "$OP_NATIVE" ]; then
                          exec "$OP_NATIVE" "$@"
                        fi
                        # Find op.exe via Windows PATH (available in WSL via interop)
                        OP_EXE=$(IFS=:; for p in $PATH; do
                          [ -f "$p/op.exe" ] && echo "$p/op.exe" && break
                        done)
                        if [ -z "$OP_EXE" ]; then
                          echo "[ERROR] op.exe not found in PATH" >&2
                          exit 1
                        fi
                        OP_VARS=$(env | grep ^OP_ | cut -d= -f1 | tr '\n' ':')
                        export WSLENV="''${WSLENV:-}:''${OP_VARS%:}"
                        exec "$OP_EXE" "$@"
                      ''
                      + "\n"
                    )
                  } -; then
                  ${pkgs.coreutils}/bin/rm -- /usr/local/bin/op
                fi
              fi
            '';
          };

          # Generate CDI spec on each activation so kind worker nodes can mount
          # /etc/cdi and use GPU resources through containerd CDI.
          nvidiaCdi = {
            deps = [ "wslWhoami" ];
            text = ''
              mkdir -p /etc/cdi
              ${pkgs.nvidia-container-toolkit}/bin/nvidia-ctk cdi generate \
                --output /etc/cdi/nvidia.yaml 2>/dev/null || true
            '';
          };
        };

        # PAM integration for gnome-keyring: auto-unlocks the keyring on login when a
        # proper PAM session is used. The daemon itself is started by the Home Manager
        # user systemd service in homeModules.wsl to avoid a duplicate
        # instance competing for the org.freedesktop.secrets D-Bus name.
        security.pam.services.login.enableGnomeKeyring = true;

      };
    darwin =
      {
        pkgs,
        inputs,
        sudoUser,
        currentUser,
        ...
      }:
      let
        user =
          if sudoUser != "" then
            sudoUser
          else if currentUser != "" then
            currentUser
          else
            throw "Unable to determine the macOS user: SUDO_USER and USER are both empty.";
      in
      {
        imports = [
          systemDefaults
          inputs.home-manager.darwinModules.home-manager
          ./modules/docker.nix
          tools.darwin
        ];

        # nix-darwin installs fonts; nix/modules/fonts configures Home Manager fontconfig clients.
        fonts.packages = (import ./modules/fonts.nix { inherit pkgs; }).fonts.packages;

        time.timeZone = "Asia/Tokyo";

        system = {
          primaryUser = user;
          stateVersion = 6;
          tools.darwin-uninstaller.enable = true;
          defaults.loginwindow = {
            GuestEnabled = false;
            SHOWFULLNAME = false;
          };
        };

        nix = {
          # Use the native weekly optimiser; auto-optimise-store is unsafe on Darwin.
          optimise.automatic = true;
          gc.interval = [
            {
              Weekday = 7;
              Hour = 3;
              Minute = 15;
            }
          ];
          # Collect unreferenced paths during builds below 10 GiB of free space.
          settings.min-free = 10 * 1024 * 1024 * 1024;
        };

        # nix-darwin's generated documentation currently passes a removed
        # nixos-render-docs flag. Omit the optional manual artifacts.
        documentation.enable = false;

        nix-homebrew = {
          enable = true;
          enableRosetta = true;
          inherit user;
          autoMigrate = true;
        };

        homebrew = {
          enable = true;
          casks = [
            "docker-desktop"
            "steam"
          ];
          # nix-darwin installs and upgrades declared casks through Homebrew Bundle.
          greedyCasks = true;
          onActivation = {
            autoUpdate = true;
            upgrade = true;
            # Remove undeclared Homebrew packages, including cask-defined settings/data.
            cleanup = "zap";
            extraEnv = {
              HOMEBREW_AUTO_UPDATE_SECS = "86400";
              HOMEBREW_NO_ENV_HINTS = "1";
            };
          };
        };

        users.users.${user}.home = "/Users/${user}";

        home-manager = {
          backupFileExtension = "hm-backup";
          users.${user} = homeModules.darwin;
        };
      };
  };
  homeModules = {
    common =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        imports = [
          tools.homeManager
          ./modules/1password
          ./modules/ai_agents/mcp.nix
          (import ./modules/ai_agents/chatgpt).homeManager
          ./modules/ai_agents/hermes
          ./modules/editors/nvim
          ./modules/fonts
          ./modules/git
          ./modules/lazygit
          ./modules/ssh.nix
          ./modules/herdr
          ./modules/shells/bash
          ./modules/shells/plugins/starship
          ./modules/shells/plugins/bat.nix
          ./modules/shells/plugins/eza.nix
          ./modules/shells/plugins/fd.nix
          ./modules/shells/plugins/fzf.nix
          ./modules/shells/plugins/ripgrep.nix
          ./modules/shells/plugins/zoxide.nix
          ./modules/shells/plugins/zsh-patina.nix
          ./modules/shells/zsh
          ./modules/terminals/ghostty
          ./modules/terminals/wezterm
        ];

        dotfiles.onePassword = {
          account = lib.mkDefault "EJLA3HRAVZBCXIQ7SRSFGQBTNU";
          ssh.publicKey = lib.mkDefault "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFMpL8l17Y0Lci3Y0ZsgnUz75XiHUrQn5vC6XyHZp7wC";
        };

        home = {
          username = lib.mkDefault "rurusasu";
          stateVersion = lib.mkDefault "26.05";
          preferXdgDirectories = true;

          # Shared user commands, preserving the previous Bash login precedence.
          sessionPath = [
            "$HOME/.bun/bin"
            "$HOME/.local/bin"
            "$HOME/bin"
            "$HOME/.local/npm/bin"
          ];
        };

        xdg.enable = true;

        # Integrated homes inherit the system package; standalone homes use the same Lix.
        nix = {
          package = lib.mkDefault pkgs.lixPackageSets.stable.lix;
          gc = {
            # Integrated homes use the OS collector; standalone homes use a user timer.
            automatic = !config.submoduleSupport.enable;
            dates = "weekly";
            options = "--delete-old";
          };
        };

      };
    darwin =
      {
        config,
        lib,
        pkgs,
        osConfig ? null,
        ...
      }:
      let
        trackpad = {
          Clicking = true;
          TrackpadRightClick = true;
        };
        dockerHost = "unix://${config.home.homeDirectory}/.docker/run/docker.sock";
        logDirectory = "${config.home.homeDirectory}/Library/Logs";
      in
      {
        imports = [
          tools.chatgpt
          ./home/keybindings/darwin.nix
          ./modules/discord
          homeModules.common
        ];

        home = {
          # System integration supplies the host home with higher priority.
          homeDirectory = lib.mkDefault "/Users/${config.home.username}";

          sessionVariables = {
            # Homebrew's default is already 24 hours; keep that interval explicit
            # for interactive shells and tools launched from the Home Manager session.
            HOMEBREW_AUTO_UPDATE_SECS = "86400";
            # Let native op use the unlocked 1Password desktop app integration.
            OP_BIOMETRIC_UNLOCK_ENABLED = "true";
          };

          sessionPath = [
            "/opt/homebrew/bin"
            "/opt/homebrew/sbin"
          ];
        };

        programs.git.signing.signer = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";

        targets.darwin.defaults = {
          "com.apple.dock" = {
            tilesize = 50;
            autohide = true;
            launchanim = true;
            show-process-indicators = true;
            show-recents = false;
            persistent-apps = [
              "/System/Applications/Apps.app"
              "${config.home.homeDirectory}/Applications/Home Manager Apps/ChatGPT.app"
              "/Applications/Nix Apps/Dia.app"
              "${config.home.homeDirectory}/Applications/Home Manager Apps/Ghostty.app"
              "/Applications/Nix Apps/Obsidian.app"
            ];
            persistent-others = [ ];
            showDesktopGestureEnabled = true;
            showMissionControlGestureEnabled = true;
            showAppExposeGestureEnabled = false;
            showLaunchpadGestureEnabled = false;
          };

          "com.apple.AppleMultitouchTrackpad" = trackpad;
          "com.apple.driver.AppleBluetoothMultitouch.trackpad" = trackpad;

          "com.apple.finder" = {
            NewWindowTarget = "PfHm";
            _FXShowPosixPathInTitle = true;
            AppleShowAllExtensions = true;
            FXEnableExtensionChangeWarning = true;
            QuitMenuItem = true;
            ShowPathbar = true;
            ShowStatusBar = true;
          };

          NSGlobalDomain = {
            AppleShowAllExtensions = true;
            "com.apple.swipescrolldirection" = true;
            AppleInterfaceStyle = "Dark";
            NSAutomaticCapitalizationEnabled = false;
            NSAutomaticDashSubstitutionEnabled = false;
            NSAutomaticPeriodSubstitutionEnabled = false;
            NSAutomaticQuoteSubstitutionEnabled = false;
            NSAutomaticSpellingCorrectionEnabled = false;
          };
        };

        # Dictionary additions preserve unrelated application-specific shortcuts.
        home.activation.globalZoomShortcut = lib.hm.dag.entryAfter [ "setDarwinDefaults" ] ''
          run /usr/bin/defaults write -g NSUserKeyEquivalents -dict-add "Zoom" "@^m"
          run /usr/bin/defaults write -g NSUserKeyEquivalents -dict-add "拡大／縮小" "@^m"
        '';

        home.activation.refreshDarwinSettings =
          lib.hm.dag.entryAfter
            [
              "setDarwinDefaults"
              "globalZoomShortcut"
              "omarchySymbolicHotkeys"
            ]
            ''
              if /usr/bin/pgrep -u "$UID" -x Dock >/dev/null; then
                run /usr/bin/killall -qu ${lib.escapeShellArg config.home.username} Dock
              fi
              run /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
            '';

        # GUI apps use the same 1Password socket as this user's shell sessions.
        launchd.agents.onepassword-ssh-environment = {
          enable = true;
          config = {
            ProgramArguments = [
              "/bin/launchctl"
              "setenv"
              "SSH_AUTH_SOCK"
              config.home.sessionVariables.SSH_AUTH_SOCK
            ];
            RunAtLoad = true;
          };
        };

        launchd.agents.tool-cache-maintenance = {
          enable = true;
          config = {
            ProgramArguments = [
              (lib.getExe (
                pkgs.writeShellApplication {
                  name = "tool-cache-maintenance";
                  runtimeInputs = [
                    pkgs.uv
                    pkgs.go
                  ];
                  text = ''
                    status=0

                    run_cleanup() {
                      local name="$1"
                      shift
                      printf 'Cleaning %s cache\n' "$name"
                      if "$@"; then
                        printf 'Finished %s cache cleanup\n' "$name"
                      else
                        local result=$?
                        printf '%s cache cleanup failed (exit %s)\n' "$name" "$result" >&2
                        status=1
                      fi
                    }

                    run_cleanup uv uv cache prune
                    # Keep downloaded modules and project outputs; rebuild this cache as needed.
                    run_cleanup go go clean -cache

                    # Cargo already garbage-collects its global cache. Do not sweep project target/.
                    if command -v docker >/dev/null 2>&1; then
                      # Pin Docker Desktop's local socket, regardless of context/environment overrides.
                      if docker --host ${lib.escapeShellArg dockerHost} info --format '{{.ServerVersion}}' >/dev/null; then
                        run_cleanup docker docker --host ${lib.escapeShellArg dockerHost} builder prune --force
                      else
                        printf 'Skipping Docker build cache: local Docker Desktop is unavailable\n' >&2
                      fi
                    else
                      printf 'Skipping Docker build cache: Docker CLI is unavailable\n' >&2
                    fi

                    exit "$status"
                  '';
                }
              ))
            ];
            EnvironmentVariables.PATH = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin";
            StartCalendarInterval =
              if osConfig != null then
                osConfig.nix.gc.interval
              else
                lib.hm.darwin.mkCalendarInterval (builtins.head config.nix.gc.dates);
            RunAtLoad = false;
            ProcessType = "Background";
            StandardOutPath = "${logDirectory}/tool-cache-maintenance.log";
            StandardErrorPath = "${logDirectory}/tool-cache-maintenance.log";
          };
        };

        home.activation.cacheMaintenanceLogDirectory = lib.hm.dag.entryBefore [ "setupLaunchAgents" ] ''
          run mkdir -p -- ${lib.escapeShellArg logDirectory}
        '';
      };
    wsl =
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
          tools.wslDesktop
          tools.chatgptCli
          homeModules.common
          ./home/keybindings/windows-export.nix
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
              source = ./home/op-ssh-sign-wsl;
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
      };
    linux =
      args@{
        config,
        lib,
        ...
      }:
      let
        currentUser = builtins.getEnv "USER";
        currentHome = builtins.getEnv "HOME";
        # NixOS supplies account identity through Home Manager osConfig.
        hasCurrentUser = !(args ? osConfig) && currentUser != "" && currentUser != "root";
      in
      {
        home = {
          username = lib.mkIf hasCurrentUser currentUser;
          homeDirectory = lib.mkDefault (
            if hasCurrentUser && currentHome != "" then currentHome else "/home/${config.home.username}"
          );
        };

        imports = [
          tools.linuxDesktop
          tools.chatgpt
          ./modules/discord
          homeModules.common
        ];

        programs.git.signing.signer = "/opt/1Password/op-ssh-sign";
      };
  };
in
{
  inherit hostModules homeModules;
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    {
      apps =
        if pkgs.stdenv.hostPlatform.isDarwin then
          {
            darwin-rebuild.program = lib.getExe inputs.nix-darwin.packages.${system}.darwin-rebuild;
          }
        else
          {
            home-manager.program = lib.getExe inputs.home-manager.packages.${system}.home-manager;
          };
      packages = {
        keybindings-json = (pkgs.formats.json { }).generate "keybindings.json" (
          import ./home/keybindings/bindings.nix { inherit lib; }
        );
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        darwin-dia-browser = import ./modules/browsers/dia {
          inherit inputs;
          pkgs = import pkgs.path {
            inherit system;
            config.allowUnfree = true;
          };
        };
      };
    };

  configurations =
    let
      hardwareConfig =
        let
          configured = builtins.getEnv "DOTFILES_NIXOS_HARDWARE_CONFIG";
        in
        if configured != "" then
          configured
        else if builtins.pathExists /etc/nixos/hardware-configuration.nix then
          "/etc/nixos/hardware-configuration.nix"
        else
          "";
      mkHome =
        system: homeModule:
        inputs.home-manager.lib.homeManagerConfiguration {
          pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          extraSpecialArgs = { inherit inputs; };
          modules = [ homeModule ];
        };
    in
    {
      homeConfigurations = {
        "aarch64-darwin" = mkHome "aarch64-darwin" homeModules.darwin;
        "x86_64-linux" = mkHome "x86_64-linux" homeModules.linux;
        "aarch64-linux" = mkHome "aarch64-linux" homeModules.linux;
      };
      nixosConfigurations = {
        nixos = inputs.nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            { nixpkgs.hostPlatform = "x86_64-linux"; }
            inputs.nixos-wsl.nixosModules.wsl
            hostModules.wsl
          ];
        };
      }
      // inputs.nixpkgs.lib.optionalAttrs (hardwareConfig != "") {
        linux = inputs.nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            { nixpkgs.hostPlatform = builtins.currentSystem or "x86_64-linux"; }
            (/. + hardwareConfig)
            hostModules.linux
          ];
        };
      };
      darwinConfigurations.macos = inputs.nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = {
          inherit inputs;
          sudoUser = builtins.getEnv "SUDO_USER";
          currentUser = builtins.getEnv "USER";
        };
        modules = [
          inputs.nix-homebrew.darwinModules.nix-homebrew
          hostModules.darwin
        ];
      };
    };
}
