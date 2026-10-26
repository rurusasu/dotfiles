# Consolidated host definitions, Home Manager defaults, and configuration registration.
inputs:
let
  systemDefaults =
    {
      inputs,
      pkgs,
      platform,
      ...
    }:
    let
      defaults = {
        user = "rurusasu";
        nixosUser = "nixos";
        stateVersion = "26.05";
        darwinStateVersion = 6;
      };
      nixPackage = pkgs.lixPackageSets.stable.lix;
      gc = {
        automatic = true;
        options = "--delete-old";
      };
    in
    {
      _module.args = defaults;
      time.timeZone = "Asia/Tokyo";
      nix = {
        package = nixPackage;
        inherit gc;
        settings = {
          min-free = 10 * 1024 * 1024 * 1024;
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          extra-substituters = [ "https://cache.numtide.com" ];
          extra-trusted-public-keys = [
            "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
          ];
        };
      };
      nixpkgs.config.allowUnfree = true;
      programs.zsh = {
        enable = true;
        enableGlobalCompInit = false;
      };
      home-manager = {
        backupFileExtension = "hm-backup";
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = { inherit inputs; };
        sharedModules = [
          ({ config, lib, ... }: {
            imports = [
              ./modules/1password
              ./modules/ai_agents/mcp.nix
              ./modules/ai_agents/hermes
              ./modules/editors/nvim
              ./modules/fonts
              ./modules/git
              ./modules/git/ghq.nix
              ./modules/git/gwq.nix
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

            home = {
              stateVersion = lib.mkDefault defaults.stateVersion;
              preferXdgDirectories = true;
              packages =
                with pkgs;
                [
                  yq-go
                  gh
                  btop
                  lazydocker
                  uv
                  go-task
                  pre-commit
                  powershell
                  bats
                  comfyui
                  # Orca is the AI IDE, not the GNOME screen reader.
                  inputs.llm-agents.packages.${stdenv.hostPlatform.system}.orca
                  (
                    if stdenv.hostPlatform.isDarwin then
                      inputs.llm-agents.packages.${stdenv.hostPlatform.system}.dsh
                    else
                      deepseek-harness
                  )
                ]
                ++
                  lib.optionals
                    (builtins.elem platform [
                      "wsl"
                      "darwin"
                    ])
                    [
                      opencode
                      pi-coding-agent
                      tuios
                    ]
                ++ lib.optionals (!config.submoduleSupport.enable) [ config.nix.package ];
            };
            xdg.enable = true;
            programs = {
              home-manager.enable = true;
              direnv.enable = true;
              jq.enable = true;
            };
            nix = {
              package = lib.mkDefault nixPackage;
              gc = gc // {
                automatic = !config.submoduleSupport.enable;
                dates = "daily";
              };
            };
          })
          ({ config, lib, ... }: {
            home.packages = with pkgs; [
              obsidian
              _1password-gui
            ];
            imports =
              {
                darwin = [
                  (import ./modules/ai_agents/chatgpt).desktop
                  {
                    home = {
                      packages = with pkgs; [
                        coreutils
                        tart
                        raycast
                        (import ./modules/browsers/dia { inherit inputs pkgs; })
                      ];
                      sessionVariables = {
                        HOMEBREW_AUTO_UPDATE_SECS = "86400";
                        OP_BIOMETRIC_UNLOCK_ENABLED = "true";
                      };
                      sessionPath = pkgs.lib.mkAfter [
                        "/opt/homebrew/bin"
                        "/opt/homebrew/sbin"
                      ];
                    };
                    programs.git.signing.signer = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";

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
                  }
                  ./modules/aerospace
                  ./modules/discord
                  ./modules/desktop.nix
                ];
                linux = [
                  (import ./modules/browsers/chrome).homeManager
                  (import ./modules/ai_agents/chatgpt).desktop
                  ./modules/discord
                  {
                    home.packages = [ pkgs.nautilus ];
                    programs.git.signing.signer = "/opt/1Password/op-ssh-sign";
                  }
                ];
                wsl = [
                  (import ./modules/browsers/chrome).wsl
                  (import ./modules/ai_agents/chatgpt).cli
                  ./modules/superfile
                  ./home/keybindings/windows-export.nix
                  ./modules/fcitx5.nix
                  ./modules/gnome-keyring
                  ./modules/editors/vscode.nix
                  (
                    let
                      graphicsEnvironment = {
                        LD_LIBRARY_PATH = "/run/opengl-driver/lib";
                        GALLIUM_DRIVER = "d3d12";
                        WARP_ENABLE_WAYLAND = "1";
                      };
                    in
                    {
                      dotfiles = {
                        keybindings.fromWindowsExport = true;
                        gwq.settings.worktree.basedir = "/mnt/d/worktrees";
                      };
                      programs = {
                        git = {
                          signing.signer = "${config.home.homeDirectory}/.local/bin/op-ssh-sign-wsl";
                          settings.ghq.root = [ "/mnt/d" ];
                        };
                        starship.settings.git_status.windows_starship = "starship.exe";
                        zsh = {
                          initContent = lib.mkBefore ''
                            zstyle ':autocomplete:' delay 0.15
                            zstyle ':autocomplete:list-choices:' min-input 2
                          '';
                          shellAliases = {
                            nrs = "task --dir ~/.dotfiles nrs";
                            nrt = "sudo nixos-rebuild test --flake ~/.dotfiles --impure";
                            nrb = "sudo nixos-rebuild boot --flake ~/.dotfiles --impure";
                          };
                        };
                      };
                      xdg.configFile."zsh-patina/config.toml".text = ''
                        [highlighting]
                        dynamic = { callables = false, paths = "complete" }
                      '';
                      home = {
                        packages = with pkgs; [
                          nautilus
                          spotify
                          signal-desktop
                        ];
                        sessionVariables = graphicsEnvironment // {
                          _ZO_EXCLUDE_DIRS = "/mnt/wsl/*:/mnt/wslg/*";
                          WSLENV = "OP_ACCOUNT/u";
                          OP_ACCOUNT = config.dotfiles.onePassword.account;
                          STARSHIP_CONFIG = lib.mkForce (
                            toString config.home.file.${config.programs.starship.configPath}.source
                          );
                        };
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
                              export WSLENV="''${WSLENV}:''${OP_VARS%:}"
                              exec "$OP_EXE" "$@"
                            '';
                          };
                          ".local/bin/op-ssh-sign-wsl" = {
                            source = ./modules/1password/op-ssh-sign-wsl;
                            executable = true;
                            force = true;
                          };
                        };
                      };
                      systemd.user.sessionVariables = graphicsEnvironment // {
                        DISPLAY = ":0";
                        WAYLAND_DISPLAY = "wayland-0";
                      };
                    }
                  )
                ];
              }
              .${platform};
          })
        ];
      };
      imports = [
        ./modules/docker.nix
        (
          { config, lib, ... }:
          let
            user =
              if platform == "darwin" then
                config.system.primaryUser
              else if platform == "wsl" then
                config.wsl.defaultUser
              else
                defaults.nixosUser;
            repository = "${config.users.users.${user}.home}/.dotfiles";
            fontDirectory = "/usr/local/share/fonts/dotfiles-wslg";
          in
          if platform == "darwin" then
            {
              imports = [
                inputs.home-manager.darwinModules.home-manager
                inputs.nix-homebrew.darwinModules.nix-homebrew
              ];
              environment.systemPackages = [ pkgs.gh ];
              nix-homebrew = {
                enable = true;
                enableRosetta = true;
                inherit user;
                autoMigrate = true;
              };
              homebrew = {
                enable = true;
                greedyCasks = true;
                casks = [
                  "docker-desktop"
                  "steam"
                ];
                onActivation = {
                  autoUpdate = true;
                  upgrade = true;
                  cleanup = "zap";
                  extraEnv = {
                    HOMEBREW_AUTO_UPDATE_SECS = "86400";
                    HOMEBREW_NO_ENV_HINTS = "1";
                  };
                };
              };
              fonts.packages = (import ./modules/fonts.nix { inherit pkgs; }).fonts.packages;
              system = {
                stateVersion = defaults.darwinStateVersion;
                defaults.loginwindow = {
                  GuestEnabled = false;
                  SHOWFULLNAME = false;
                };
              };
              nix = {
                optimise.automatic = true;
                gc = {
                  interval = [
                    {
                      Hour = 3;
                      Minute = 15;
                    }
                  ];
                };
              };
              # The locked nixos-render-docs rejects nix-darwin's manual flags.
              documentation.enable = false;
              users.users.${user}.home = "/Users/${user}";
              home-manager.users.${user} = { };
            }
          else
            {
              imports = [
                ./modules/fonts.nix
                inputs.home-manager.nixosModules.home-manager
              ]
              ++ (
                if platform == "wsl" then
                  [
                    inputs.nixos-wsl.nixosModules.wsl
                    ./modules/nvidia.nix
                    {
                      # Retire only the exact wrapper previously copied by this module. Keep
                      # unrelated administrator files and symlinks at this path untouched.
                      system.activationScripts.retireSystemOpWrapper = {
                        text = ''
                          if [ -f /usr/local/bin/op ] && [ ! -L /usr/local/bin/op ]; then
                            # The bash store path can change independently of the wrapper body.
                            if ${pkgs.coreutils}/bin/head -n 1 /usr/local/bin/op | \
                              ${pkgs.gnugrep}/bin/grep -Eq '^#!/nix/store/[a-z0-9]{32}-bash-[^/]+/bin/bash$' && \
                              ${pkgs.coreutils}/bin/tail -n +2 /usr/local/bin/op | \
                              ${pkgs.diffutils}/bin/cmp -s ${
                                pkgs.writeText "legacy-op-wrapper-body" (
                                  ''
                                    OP_NATIVE="/etc/profiles/per-user/${config.wsl.defaultUser}/bin/op"
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
                      system.activationScripts.wslgFonts = {
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
                      assertions = [
                        {
                          assertion = builtins.substring 0 1 repository == "/" && !(lib.hasInfix "*" repository);
                          message = "WSL Git trust requires one absolute checkout path without wildcards.";
                        }
                      ];
                      # Home Manager starts the keyring; PAM unlocks it at login.
                      security.pam.services.login.enableGnomeKeyring = true;
                      wsl = {
                        enable = true;
                        defaultUser = lib.mkDefault defaults.nixosUser;
                        useWindowsDriver = true;
                        wslConf.network.generateHosts = false;
                      };
                      i18n.extraLocales = [ "ja_JP.UTF-8/UTF-8" ];
                      programs = {
                        git = {
                          enable = true;
                          config.safe.directory = [ repository ];
                        };
                        dconf.enable = true;
                        nix-ld = {
                          enable = true;
                          libraries = with pkgs; [
                            wayland
                            libxkbcommon
                          ];
                        };
                      };
                      systemd.user.services.nixos-activation = {
                        wants = [ "graphical-session.target" ];
                        after = [ "graphical-session.target" ];
                      };
                      xdg.portal = {
                        enable = true;
                        extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
                        config.common.default = "*";
                      };
                    }
                  ]
                else
                  [
                    {
                      programs.hyprland.enable = true;
                      home-manager.sharedModules = [
                        ./modules/hyprland
                        {
                          home.packages = with pkgs; [
                            firefox
                            fuzzel
                          ];
                        }
                      ];
                    }
                  ]
              );
              fonts.fontDir.enable = true;
              system.stateVersion = defaults.stateVersion;
              users.users.${user} = {
                isNormalUser = true;
                shell = pkgs.zsh;
                linger = true;
                extraGroups = [
                  "wheel"
                  "docker"
                ];
              };
              home-manager.users.${user} = { };
            }
        )
      ];
    };

in
{
  inherit systemDefaults;
  perSystem =
    {
      config,
      pkgs,
      lib,
      system,
      ...
    }:
    {
      treefmt = {
        imports = [ ./treefmt.nix ];
        _module.args.psscriptanalyzerSrc = inputs.psscriptanalyzer;
      };
      devShells.default = pkgs.mkShell {
        inputsFrom = [ config.treefmt.build.devShell ];
        packages = [
          pkgs.statix
          pkgs.deadnix
        ];
      };
      apps =
        if pkgs.stdenv.hostPlatform.isDarwin then
          {
            darwin-rebuild.program = lib.getExe inputs.nix-darwin.packages.${system}.darwin-rebuild;
          }
        else
          {
            home-manager.program = lib.getExe inputs.home-manager.packages.${system}.home-manager;
          };
      packages = lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
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
      hardwareConfig = /etc/nixos/hardware-configuration.nix;
      mkHome =
        system: platform:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          base = systemDefaults { inherit inputs pkgs platform; };
        in
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = { inherit inputs; };
          modules = pkgs.lib.reverseList base.home-manager.sharedModules ++ [
            ({ config, lib, ... }: {
              home = {
                username = lib.mkDefault base._module.args.user;
                homeDirectory = lib.mkDefault "${
                  if pkgs.stdenv.hostPlatform.isDarwin then "/Users" else "/home"
                }/${config.home.username}";
              };
            })
          ];
        };
    in
    {
      homeConfigurations = {
        "aarch64-darwin" = mkHome "aarch64-darwin" "darwin";
        "x86_64-linux" = mkHome "x86_64-linux" "linux";
        "aarch64-linux" = mkHome "aarch64-linux" "linux";
      };
      nixosConfigurations = {
        nixos = inputs.nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs;
            platform = "wsl";
          };
          modules = [
            { nixpkgs.hostPlatform = "x86_64-linux"; }
            systemDefaults
          ];
        };
      }
      // inputs.nixpkgs.lib.optionalAttrs (builtins.pathExists hardwareConfig) {
        linux = inputs.nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit inputs;
            platform = "linux";
          };
          modules = [
            { nixpkgs.hostPlatform = builtins.currentSystem; }
            hardwareConfig
            systemDefaults
          ];
        };
      };
      darwinConfigurations.macos = inputs.nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = {
          inherit inputs;
          platform = "darwin";
        };
        modules = [
          ({ user, ... }: { system.primaryUser = user; })
          systemDefaults
        ];
      };
    };
}
