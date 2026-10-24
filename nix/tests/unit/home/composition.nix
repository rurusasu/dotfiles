{ inputs }:
let
  fixtures = import ../../fixtures/packages.nix { inherit inputs; };
  mkPkgs = system: fixtures.mkPkgs system;
  configuredChrome = home: import ../../../modules/browsers/chrome { inherit (home) pkgs; };

  baseModule = _: {
    home = {
      username = "test-user";
      homeDirectory = "/home/test-user";
      stateVersion = "25.05";
    };
  };

  mkHome =
    {
      system,
      module,
      specialArgs ? { },
    }:
    let
      pkgs = mkPkgs system;
    in
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs;
      }
      // specialArgs;
      modules = [
        baseModule
        module
      ]
      ++ ((import (
        if pkgs.stdenv.hostPlatform.isDarwin then
          ../../../hosts/aarch64-darwin/platform.nix
        else
          ../../../hosts/shared/nixos/platform.nix
      ) { inherit pkgs inputs; }).home-manager.sharedModules or [ ]
      )
      ++ [
        ../../../modules/terminals/ghostty/defaults.nix
        ../../../modules/terminals/wezterm/defaults.nix
      ];
    };

  common = mkHome {
    system = "x86_64-linux";
    module = ../../../home/common.nix;
  };

  linux = mkHome {
    system = "x86_64-linux";
    module = ../../../hosts/shared/linux-home.nix;
  };

  wsl = mkHome {
    system = "x86_64-linux";
    module = ../../../hosts/x86_64-linux/wsl/home.nix;
  };

  darwin = mkHome {
    system = "aarch64-darwin";
    module = ../../../hosts/aarch64-darwin/home.nix;
    specialArgs = {
    };
  };

  darwinPackages = {
    pkgs = mkPkgs "aarch64-darwin";
    system = fixtures.darwin.config.environment.systemPackages;
    contains =
      package: packages: builtins.any (candidate: candidate.drvPath == package.drvPath) packages;
  };

in
{
  testLinuxDesktopGuiUsesUdevInGtkAndSettingsPortal = {
    expr = {
      homes =
        map
          (home: {
            enabled = home.config.gtk.enable;
            gtk3 = home.pkgs.lib.hasInfix "gtk-font-name=UDEV Gothic NF 11" (
              home.config.xdg.configFile."gtk-3.0/settings.ini".text or ""
            );
            gtk4 = home.pkgs.lib.hasInfix "gtk-font-name=UDEV Gothic NF 11" (
              home.config.xdg.configFile."gtk-4.0/settings.ini".text or ""
            );
            portalFont = home.config.dconf.settings."org/gnome/desktop/interface"."font-name" or null;
          })
          [
            wsl
            linux
          ];
      commonEnabled = common.config.gtk.enable;
      darwinEnabled = darwin.config.gtk.enable;
    };
    expected = {
      homes = [
        {
          enabled = true;
          gtk3 = true;
          gtk4 = true;
          portalFont = "UDEV Gothic NF 11";
        }
        {
          enabled = true;
          gtk3 = true;
          gtk4 = true;
          portalFont = "UDEV Gothic NF 11";
        }
      ];
      commonEnabled = false;
      darwinEnabled = false;
    };
  };
  testWslAppKeybindingsUseWindowsExportAndNativeHomesKeepNix = {
    expr =
      map
        (home: home.pkgs.lib.attrByPath [ "dotfiles" "keybindings" "fromWindowsExport" ] false home.config)
        [
          wsl
          linux
          darwin
        ];
    expected = [
      true
      false
      false
    ];
  };
  testCodexConfigurationIsOwnedByHomeManagerAcrossHomes = {
    expr =
      map
        (home: {
          enabled = home.config.programs.codex.enable;
          appProvided =
            home.config.programs.codex.package == null || home.config.programs.codex.package ? chatgpt;
          mutable = home.config.programs.codex.mutableSettings;
          cleanup = home.config.programs.codex.settings.desktop;
          agents = home.config.programs.codex.settings.agents.fast_worker.config_file;
          hookCount = builtins.length (builtins.head home.config.programs.codex.hooks.PreToolUse).hooks;
          rules = builtins.attrNames home.config.programs.codex.rules;
          contextTakeover = home.config.home.file.".codex/AGENTS.override.md".force;
          mergeActivation = home.config.home.activation ? codexMutableSettings;
          noImmutableConfig = !(home.config.home.file ? ".codex/config.toml");
        })
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      enabled = true;
      appProvided = true;
      mutable = true;
      cleanup = {
        worktree-auto-cleanup-enabled = true;
        worktree-keep-count = 15;
      };
      agents = "/home/test-user/.codex/agents/fast_worker.toml";
      hookCount = 2;
      rules = [
        "commands"
        "nix"
        "python"
        "safety"
        "starlark"
      ];
      contextTakeover = true;
      mergeActivation = true;
      noImmutableConfig = true;
    }) 3;
  };

  testPnpmIsNotInstalled = {
    expr =
      map
        (home: {
          enabled = home.config.programs.pnpm.enable;
          environment = home.config.home.sessionVariables ? PNPM_HOME;
        })
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      enabled = false;
      environment = false;
    }) 3;
  };

  testStandaloneHomesRunWeeklyUserGarbageCollection = {
    expr =
      map
        (home: {
          automatic = home.config.nix.gc.automatic;
          dates = home.config.nix.gc.dates;
          options = home.config.nix.gc.options;
        })
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      automatic = true;
      dates = [ "weekly" ];
      options = "--delete-old";
    }) 3;
  };

  testGitNativeSettingsAreSharedAcrossHomes = {
    expr =
      map
        (home: {
          enabled = home.config.programs.git.enable;
          gitCopies = builtins.length (
            builtins.filter (
              package: package.drvPath == home.config.programs.git.package.drvPath
            ) home.config.home.packages
          );
          ghqCopies = builtins.length (
            builtins.filter (package: package.drvPath == home.pkgs.ghq.drvPath) home.config.home.packages
          );
          gwqCopies = builtins.length (
            builtins.filter (package: package.drvPath == home.pkgs.gwq.drvPath) home.config.home.packages
          );
          relativeWorktrees = home.config.programs.git.settings.worktree.useRelativePaths or false;
          identity = home.config.programs.git.settings.user;
          core = home.config.programs.git.settings.core;
          credentials = home.config.programs.git.settings.credential;
          signing = {
            inherit (home.config.programs.git.signing) format key signByDefault;
          };
          gtrAlias = home.config.programs.git.settings.alias.gtr;
        })
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      enabled = true;
      gitCopies = 1;
      ghqCopies = 1;
      gwqCopies = 1;
      relativeWorktrees = true;
      identity = {
        name = "rurusasu";
        email = "36875744+rurusasu@users.noreply.github.com";
      };
      core = {
        editor = "nvim";
        sshCommand = "ssh";
      };
      credentials = {
        "https://github.com".helper = "!gh auth git-credential";
        "https://gist.github.com".helper = "!gh auth git-credential";
      };
      signing = {
        format = "ssh";
        key = "~/.ssh/signing_key.pub";
        signByDefault = false;
      };
      gtrAlias = "!gwq add";
    }) 3;
  };

  testGwqKeepsWslWorktreesOnTheWindowsDrive = {
    expr = map (home: home.config.dotfiles.gwq.settings) [
      linux
      wsl
      darwin
    ];
    expected = [
      {
        worktree.basedir = "/home/test-user/worktrees";
        worktree.auto_mkdir = true;
        cd.launch_shell = false;
      }
      {
        worktree.basedir = "/mnt/d/worktrees";
        worktree.auto_mkdir = true;
        cd.launch_shell = false;
      }
      {
        worktree.basedir = "/home/test-user/worktrees";
        worktree.auto_mkdir = true;
        cd.launch_shell = false;
      }
    ];
  };

  testHomeGitHasNoMutableCheckoutTrustIncludes = {
    expr = map (home: home.config.programs.git.includes) [
      linux
      wsl
      darwin
    ];
    expected = [
      [ ]
      [ ]
      [ ]
    ];
  };

  testOnePasswordGitSshPlatformIntegration = {
    expr =
      map
        (home: {
          signer = home.config.programs.git.signing.signer;
          ghqRoot = home.config.programs.git.settings.ghq.root;
          agent = home.config.programs.ssh.extraOptionOverrides.IdentityAgent;
          agentEnvironment = home.config.home.sessionVariables.SSH_AUTH_SOCK;
          opensshAgentEnabled = home.config.services.ssh-agent.enable;
          gpgSshAgentEnabled = home.config.services.gpg-agent.enableSshSupport;
          publicKeyActivationAfter = home.config.home.activation.onePasswordSshPublicKey.after;
          publicKeyIsStoreManaged = home.config.home.file ? ".ssh/signing_key.pub";
        })
        [
          linux
          wsl
          darwin
        ];
    expected = [
      {
        signer = "/opt/1Password/op-ssh-sign";
        ghqRoot = "~/ghq";
        agent = ''"/home/test-user/.1password/agent.sock"'';
        agentEnvironment = "/home/test-user/.1password/agent.sock";
        opensshAgentEnabled = false;
        gpgSshAgentEnabled = false;
        publicKeyActivationAfter = [ "writeBoundary" ];
        publicKeyIsStoreManaged = false;
      }
      {
        signer = "/home/test-user/.local/bin/op-ssh-sign-wsl";
        ghqRoot = [ "/mnt/d" ];
        agent = ''"/home/test-user/.1password/agent.sock"'';
        agentEnvironment = "/home/test-user/.1password/agent.sock";
        opensshAgentEnabled = false;
        gpgSshAgentEnabled = false;
        publicKeyActivationAfter = [ "writeBoundary" ];
        publicKeyIsStoreManaged = false;
      }
      {
        signer = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
        ghqRoot = "~/ghq";
        agent = ''"/home/test-user/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"'';
        agentEnvironment = "/home/test-user/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
        opensshAgentEnabled = false;
        gpgSshAgentEnabled = false;
        publicKeyActivationAfter = [ "writeBoundary" ];
        publicKeyIsStoreManaged = false;
      }
    ];
  };

  testNativeGitAndSshOwnTheirFilesWithoutBackups = {
    expr =
      map
        (home: {
          gitForce = home.config.xdg.configFile."git/config".force;
          legacyGitForce = home.config.home.file.".gitconfig".force;
          legacyGitHasNoSettings = !(home.pkgs.lib.hasInfix "[" home.config.home.file.".gitconfig".text);
          gitTextHasIdentity =
            home.pkgs.lib.hasInfix ''email = "36875744+rurusasu@users.noreply.github.com"''
              home.config.xdg.configFile."git/config".text;
          sshForce = home.config.home.file.".ssh/config".force;
          sshIncludes = home.config.programs.ssh.includes;
          sshDefaultsDisabled = !home.config.programs.ssh.enableDefaultConfig;
          github = home.config.programs.ssh.settings."github.com".data;
        })
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      gitForce = true;
      legacyGitForce = true;
      legacyGitHasNoSettings = true;
      gitTextHasIdentity = true;
      sshForce = true;
      sshIncludes = [ "~/.ssh/orca-docker-*.config" ];
      sshDefaultsDisabled = true;
      github = {
        header = "Host github.com";
        HostName = "github.com";
        User = "git";
        IdentityFile = "~/.ssh/signing_key.pub";
        IdentitiesOnly = true;
      };
    }) 3;
  };

  testFdStarshipAndPatinaShellIntegrationAcrossHomes = {
    expr =
      map
        (
          home:
          let
            inherit (home.pkgs.lib)
              getExe
              hasInfix
              hasSuffix
              trim
              ;
            patinaInit = ''eval "$(${getExe home.pkgs.zsh-patina} activate)"'';
          in
          {
            fdFindAlias = home.config.programs.zsh.shellAliases.find;
            starshipEnabled = home.config.programs.starship.enable;
            starshipZshIntegration = home.config.programs.starship.enableZshIntegration;
            starshipInit = hasInfix (builtins.unsafeDiscardStringContext ''eval "$(${getExe home.config.programs.starship.package} init zsh)"'') home.config.programs.zsh.initContent;
            patinaLast = hasSuffix patinaInit (trim home.config.programs.zsh.initContent);
          }
        )
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      fdFindAlias = "fd";
      starshipEnabled = true;
      starshipZshIntegration = true;
      starshipInit = true;
      patinaLast = true;
    }) 3;
  };

  testBatAndRipgrepSettingsAcrossHomes = {
    expr =
      map
        (home: {
          batEnabled = home.config.programs.bat.enable;
          ripgrepEnabled = home.config.programs.ripgrep.enable;
          batPackage = home.config.programs.bat.package.pname;
          ripgrepPackage = home.config.programs.ripgrep.package.pname;
          batConfig = home.config.programs.bat.config;
          batManPager =
            home.config.home.sessionVariables.MANPAGER
            == "${home.pkgs.bash}/bin/sh -c '${home.pkgs.unixtools.col}/bin/col -bx | ${home.config.programs.bat.package}/bin/bat -l man -p'";
          manRoffOptions = home.config.home.sessionVariables.MANROFFOPT;
          ripgrepArguments = home.config.programs.ripgrep.arguments;
          ripgrepConfigPath = home.config.home.sessionVariables.RIPGREP_CONFIG_PATH;
          ripgrepConfig = home.config.home.file."${home.config.xdg.configHome}/ripgrep/ripgreprc".text;
        })
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      batEnabled = true;
      ripgrepEnabled = true;
      batPackage = "bat";
      ripgrepPackage = "ripgrep";
      batConfig = {
        theme = "Catppuccin Mocha";
        style = "numbers,changes,header,grid";
        paging = "auto";
      };
      batManPager = true;
      manRoffOptions = "-c";
      ripgrepArguments = [
        "--smart-case"
        "--hidden"
        "--glob=!.git/*"
      ];
      ripgrepConfigPath = "/home/test-user/.config/ripgrep/ripgreprc";
      ripgrepConfig = ''
        --smart-case
        --hidden
        --glob=!.git/*
      '';
    }) 3;
  };

  testEzaZshAliasesUseConfiguredListingOptionsAcrossHomes = {
    expr =
      map
        (home: {
          enabled = home.config.programs.eza.enable;
          zshIntegration = home.config.programs.eza.enableZshIntegration;
          packageName = home.config.programs.eza.package.pname;
          inherit (home.config.programs.zsh.shellAliases)
            eza
            ls
            ll
            la
            lt
            lla
            ;
        })
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      enabled = true;
      zshIntegration = true;
      packageName = "eza";
      eza = "eza --icons auto --color auto --tree";
      ls = "eza --level=1";
      ll = "eza --level=1 --group-directories-first --time-style=long-iso";
      la = "eza --level=1 --group-directories-first --time-style=long-iso --git --hyperlink -F";
      lt = "eza --level=2 --group-directories-first --time-style=long-iso --git";
      lla = "eza -la";
    }) 3;
  };

  testFzfSharedDefaultsAcrossHomes = {
    expr =
      map
        (home: {
          enabled = home.config.programs.fzf.enable;
          defaultCommand = home.config.home.sessionVariables.FZF_DEFAULT_COMMAND or null;
          filePreview = home.config.home.sessionVariables.FZF_FILE_PREVIEW or null;
          dirPreview = home.config.home.sessionVariables.FZF_DIR_PREVIEW or null;
          fileWidgetCommand = home.config.home.sessionVariables.FZF_CTRL_T_COMMAND or null;
          fileWidgetOptions = home.config.home.sessionVariables.FZF_CTRL_T_OPTS or null;
          changeDirWidgetCommand = home.config.home.sessionVariables.FZF_ALT_C_COMMAND or null;
          changeDirWidgetOptions = home.config.home.sessionVariables.FZF_ALT_C_OPTS or null;
          defaultOptions = home.config.home.sessionVariables.FZF_DEFAULT_OPTS or null;
          bashIntegration = home.config.programs.fzf.enableBashIntegration;
          zshIntegration = home.config.programs.fzf.enableZshIntegration;
        })
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      enabled = true;
      defaultCommand = null;
      filePreview = null;
      dirPreview = null;
      fileWidgetCommand = null;
      fileWidgetOptions = null;
      changeDirWidgetCommand = null;
      changeDirWidgetOptions = null;
      defaultOptions = "--height=60% --layout=reverse --border --prompt=> ";
      bashIntegration = false;
      zshIntegration = true;
    }) 3;
  };

  testFdFzfIntegrationIsGeneratedAcrossHomes = {
    expr =
      map
        (
          home:
          let
            contains = fragment: home.pkgs.lib.hasInfix fragment home.config.programs.zsh.initContent;
          in
          {
            guarded = contains "if command -v fzf >/dev/null 2>&1; then";
            defaultCommand = contains "export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git --follow'";
            fileWidgetCommand = contains ''export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"'';
            directoryWidgetCommand = contains "export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git'";
            pathCompletion =
              contains "_fzf_compgen_path() {" && contains ''fd --hidden --exclude .git --follow . "$1"'';
            directoryCompletion =
              contains "_fzf_compgen_dir() {" && contains ''fd --type d --hidden --exclude .git --follow . "$1"'';
            obsoleteRipgrepDefault = contains "export FZF_DEFAULT_COMMAND='rg --files'";
          }
        )
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      guarded = true;
      defaultCommand = true;
      fileWidgetCommand = true;
      directoryWidgetCommand = true;
      pathCompletion = true;
      directoryCompletion = true;
      obsoleteRipgrepDefault = false;
    }) 3;
  };

  testRipgrepFzfIntegrationIsGeneratedAcrossHomes = {
    expr =
      map
        (
          home:
          let
            contains = fragment: home.pkgs.lib.hasInfix fragment home.config.programs.zsh.initContent;
          in
          {
            guarded = contains "if command -v rg >/dev/null 2>&1 && command -v fzf >/dev/null 2>&1; then";
            functionDefined = contains "rfg() {";
            initialSearch = contains "start:reload:rg --line-number --no-heading --color=always -- {q} || true";
            liveSearch = contains "change:reload:rg --line-number --no-heading --color=always -- {q} || true";
            preview = contains "bat --color=always --highlight-line {2} -- {1}";
            editor = contains ''''${EDITOR:-vi} "+$line" "$file"'';
          }
        )
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      guarded = true;
      functionDefined = true;
      initialSearch = true;
      liveSearch = true;
      preview = true;
      editor = true;
    }) 3;
  };

  testZoxideShellIntegrationsAcrossHomes = {
    expr =
      map
        (home: {
          enabled = home.config.programs.zoxide.enable;
          bashIntegration = home.config.programs.zoxide.enableBashIntegration;
          zshIntegration = home.config.programs.zoxide.enableZshIntegration;
          options = home.config.programs.zoxide.options;
          bashCommand = inputs.nixpkgs.lib.hasInfix " init bash --cmd cd" home.config.programs.bash.initExtra;
          zshCommand = inputs.nixpkgs.lib.hasInfix " init zsh --cmd cd" home.config.programs.zsh.initContent;
          customBashWidget = inputs.nixpkgs.lib.hasInfix "__zoxide_zi_widget" home.config.programs.bash.initExtra;
          customZshWidget = inputs.nixpkgs.lib.hasInfix "__zoxide_zi_widget" home.config.programs.zsh.initContent;
        })
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      enabled = true;
      bashIntegration = true;
      zshIntegration = true;
      options = [ "--cmd cd" ];
      bashCommand = true;
      zshCommand = true;
      customBashWidget = false;
      customZshWidget = false;
    }) 3;
  };

  testShellPluginsUseNativeZshIntegrationAcrossHomes = {
    expr =
      map
        (
          home:
          let
            inherit (home.pkgs.lib) getExe hasInfix;
            inherit (home.config) programs;
          in
          {
            fzf = programs.fzf.enableZshIntegration;
            eza = programs.eza.enableZshIntegration;
            zoxide = programs.zoxide.enableZshIntegration;
            fzfInit =
              let
                fzfPackage = builtins.unsafeDiscardStringContext (toString programs.fzf.package);
              in
              hasInfix "source ${fzfPackage}/share/fzf/key-bindings.zsh" programs.zsh.initContent
              && hasInfix "source ${fzfPackage}/share/fzf/completion.zsh" programs.zsh.initContent;
            zoxideInit = hasInfix (builtins.unsafeDiscardStringContext "${getExe programs.zoxide.package} init zsh") programs.zsh.initContent;
            completionsEnabled = programs.zsh.enableCompletion;
            packageCompletions = hasInfix "$profile/share/zsh/site-functions" programs.zsh.initContent;
            completionPlugin = builtins.elem "zsh-autocomplete" (
              map (plugin: plugin.name) programs.zsh.plugins
            );
          }
        )
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      fzf = true;
      eza = true;
      zoxide = true;
      fzfInit = true;
      zoxideInit = true;
      completionsEnabled = true;
      packageCompletions = true;
      completionPlugin = true;
    }) 3;
  };

  testTerminalShellIntegrationsAreGeneratedAcrossHomes = {
    expr =
      map
        (home: {
          bashEnabled = home.config.programs.bash.enable;
          bashAliases = home.pkgs.lib.hasInfix "alias ll=" home.config.programs.bash.initExtra;
          bashGhostty = home.pkgs.lib.hasInfix "shell-integration/bash/ghostty.bash" home.config.programs.bash.initExtra;
          bashWezterm = home.pkgs.lib.hasInfix "/etc/profile.d/wezterm.sh" home.config.programs.bash.initExtra;
          zshGhostty = home.pkgs.lib.hasInfix "shell-integration/zsh/ghostty-integration" home.config.programs.zsh.initContent;
          zshWezterm = home.pkgs.lib.hasInfix "/etc/profile.d/wezterm.sh" home.config.programs.zsh.initContent;
        })
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      bashEnabled = true;
      bashAliases = true;
      bashGhostty = true;
      bashWezterm = true;
      zshGhostty = true;
      zshWezterm = true;
    }) 3;
  };

  testRustToolsOutrankRetainedRustupAcrossHomes = {
    expr =
      map
        (
          home:
          let
            packages = home.config.home.packages;
            selected = target: builtins.filter (package: package.drvPath == target.drvPath) packages;
            priority = target: (builtins.head (selected target)).meta.priority or 5;
          in
          {
            analyzerWins = priority home.pkgs.rust-analyzer < priority home.pkgs.rustup;
            formatterWins = priority home.pkgs.rustfmt < priority home.pkgs.rustup;
          }
        )
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      analyzerWins = true;
      formatterWins = true;
    }) 3;
  };

  testNeovimSettingsAndRuntimeDependenciesAcrossHomes = {
    expr =
      builtins.map
        (
          home:
          let
            cfg = home.config.programs.neovim;
          in
          {
            enabled = cfg.enable;
            sideloadInit = cfg.sideloadInitLua;
            writesInit = home.config.xdg.configFile."nvim/init.lua".enable or false;
            pluginData = home.config.xdg.dataFile."nvim/site/pack/hm".enable;
            internalPackages = cfg.extraPackages == [ ];
            serverDependencies =
              builtins.all
                (package: builtins.any (extra: extra.drvPath == package.drvPath) home.config.home.packages)
                [
                  home.pkgs.gopls
                  home.pkgs.ruff
                  home.pkgs.ty
                  home.pkgs.lua-language-server
                  (home.pkgs.callPackage ../../../modules/typescript-language-server/package.nix { })
                  home.pkgs.nixfmt
                ];
            remoteInstalled = builtins.any (
              package: package.drvPath == home.pkgs.neovim-remote.drvPath
            ) home.config.home.packages;
            globalServerPackages = builtins.any (
              package:
              builtins.elem package.drvPath (
                map (server: server.drvPath) [
                  home.pkgs.nixd
                  home.pkgs.gopls
                  home.pkgs.ruff
                ]
              )
            ) home.config.home.packages;
          }
        )
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      enabled = true;
      sideloadInit = false;
      writesInit = true;
      pluginData = true;
      internalPackages = true;
      serverDependencies = true;
      remoteInstalled = true;
      globalServerPackages = true;
    }) 3;
  };

  testHeadlessHomesDoNotEnableNativeCompositor = {
    expr =
      map
        (home: {
          enabled = home.config.wayland.windowManager.hyprland.enable;
          desktopPackages = builtins.filter (
            name:
            builtins.elem name [
              "hyprland"
              "fuzzel"
              "firefox"
            ]
          ) (map (package: package.pname or package.name) home.config.home.packages);
        })
        [
          linux
          wsl
        ];
    expected = [
      {
        enabled = false;
        desktopPackages = [ ];
      }
      {
        enabled = false;
        desktopPackages = [ ];
      }
    ];
  };
  testCommonHomeModuleEvaluatesWithoutOSSpecialArgs = {
    expr = common.config.home.username;
    expected = "test-user";
  };

  testLinuxHomeModuleRetainsSharedShellConfiguration = {
    expr = builtins.elem "source ${../../../home/shells/zsh/aliases.zsh}" (
      inputs.nixpkgs.lib.splitString "\n" linux.config.programs.zsh.initContent
    );
    expected = true;
  };

  testZshUserSettingsRetainHistoryAndSourceOrderAcrossHomes = {
    expr =
      map
        (home: {
          enabled = home.config.programs.zsh.enable;
          dotDir = home.config.programs.zsh.dotDir;
          historyPath = home.config.programs.zsh.history.path;
          historySize = home.config.programs.zsh.history.size;
          historySave = home.config.programs.zsh.history.save;
          historyShared = home.config.programs.zsh.history.share;
          options = home.config.programs.zsh.setOptions;
          sources = builtins.filter (
            line:
            builtins.elem line [
              "source ${../../../home/shells/zsh/bindings.zsh}"
              "source ${../../../home/shells/zsh/aliases.zsh}"
              "source ${../../../home/shells/zsh/prompt.zsh}"
            ]
          ) (inputs.nixpkgs.lib.splitString "\n" home.config.programs.zsh.initContent);
        })
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      enabled = true;
      dotDir = "/home/test-user/.config/zsh";
      historyPath = "/home/test-user/.local/state/zsh/history";
      historySize = 10000;
      historySave = 10000;
      historyShared = true;
      options = [
        "AUTO_CD"
        "NO_BEEP"
        "NUMERIC_GLOB_SORT"
        "HIST_FCNTL_LOCK"
        "APPEND_HISTORY"
        "EXTENDED_HISTORY"
        "HIST_EXPIRE_DUPS_FIRST"
        "HIST_IGNORE_DUPS"
        "HIST_IGNORE_SPACE"
        "HIST_SAVE_NO_DUPS"
        "SHARE_HISTORY"
        "NO_HIST_FIND_NO_DUPS"
        "NO_HIST_IGNORE_ALL_DUPS"
      ];
      sources = [
        "source ${../../../home/shells/zsh/bindings.zsh}"
        "source ${../../../home/shells/zsh/aliases.zsh}"
        "source ${../../../home/shells/zsh/prompt.zsh}"
      ];
    }) 3;
  };

  testPatinaCallableLookupsAreDisabledOnlyForWsl = {
    expr = {
      wsl = builtins.fromTOML wsl.config.xdg.configFile."zsh-patina/config.toml".text;
      linuxConfigured = linux.config.xdg.configFile ? "zsh-patina/config.toml";
      darwinConfigured = darwin.config.xdg.configFile ? "zsh-patina/config.toml";
    };
    expected = {
      wsl.highlighting.dynamic = {
        callables = false;
        paths = "complete";
      };
      linuxConfigured = false;
      darwinConfigured = false;
    };
  };

  testHostPromptsUseKnownOperatingSystems = {
    expr =
      map
        (home: {
          symbol = home.config.dotfiles.starship.osSymbol;
          runtimeOsDetection = !home.config.programs.starship.settings.os.disabled;
          windowsStarship = home.config.programs.starship.settings.git_status.windows_starship or null;
        })
        [
          linux
          wsl
          darwin
        ];
    expected = [
      {
        symbol = "❄️ ";
        runtimeOsDetection = false;
        windowsStarship = null;
      }
      {
        symbol = "❄️ ";
        runtimeOsDetection = false;
        windowsStarship = "starship.exe";
      }
      {
        symbol = "🍎 ";
        runtimeOsDetection = false;
        windowsStarship = null;
      }
    ];
  };

  testWslWindowsPromptReadsTheGeneratedConfigDirectly = {
    expr = {
      wslUsesSource =
        wsl.config.home.sessionVariables.STARSHIP_CONFIG
        == toString wsl.config.home.file.${wsl.config.programs.starship.configPath}.source;
      linuxUsesConfigPath =
        linux.config.home.sessionVariables.STARSHIP_CONFIG == linux.config.programs.starship.configPath;
      darwinUsesConfigPath =
        darwin.config.home.sessionVariables.STARSHIP_CONFIG == darwin.config.programs.starship.configPath;
    };
    expected = {
      wslUsesSource = true;
      linuxUsesConfigPath = true;
      darwinUsesConfigPath = true;
    };
  };

  testNRShellAliasUsesPlatformInstallCommand = {
    expr = {
      wsl = wsl.config.programs.zsh.shellAliases.nrs;
      linux = linux.config.programs.zsh.shellAliases.nrs;
      darwin = darwin.config.programs.zsh.shellAliases.nrs;
    };
    expected = {
      wsl = "task --dir ~/.dotfiles nrs";
      linux = "~/.dotfiles/install.sh";
      darwin = "~/.dotfiles/install.sh";
    };
  };

  testLinuxHomeModuleDoesNotReceiveDarwinSessionVariables = {
    expr = builtins.hasAttr "HOMEBREW_AUTO_UPDATE_SECS" linux.config.home.sessionVariables;
    expected = false;
  };

  testWSLHomeModuleOwnsWSLSessionVariables = {
    expr = {
      browser = wsl.config.home.sessionVariables.BROWSER;
      inputMethod = wsl.config.home.sessionVariables.GTK_IM_MODULE;
      qtInputMethod = wsl.config.home.sessionVariables.QT_IM_MODULE;
      xModifiers = wsl.config.home.sessionVariables.XMODIFIERS;
      globalLanguage = wsl.config.home.sessionVariables.LANG or null;
      globalLocale = wsl.config.home.sessionVariables.LC_ALL or null;
      zoxideExclusion = wsl.config.home.sessionVariables._ZO_EXCLUDE_DIRS;
      onePasswordAccount = wsl.config.home.sessionVariables.OP_ACCOUNT;
      windowsEnvironment = wsl.config.home.sessionVariables.WSLENV;
      signer = wsl.config.programs.git.signing.signer;
      signerBridge = {
        source = wsl.config.home.file.".local/bin/op-ssh-sign-wsl".source;
        executable = wsl.config.home.file.".local/bin/op-ssh-sign-wsl".executable;
      };
    };
    expected = {
      browser = "${configuredChrome wsl}/bin/google-chrome-stable";
      inputMethod = "fcitx";
      qtInputMethod = "fcitx";
      xModifiers = "@im=fcitx";
      globalLanguage = null;
      globalLocale = null;
      zoxideExclusion = "/mnt/wsl/*:/mnt/wslg/*";
      onePasswordAccount = "EJLA3HRAVZBCXIQ7SRSFGQBTNU";
      windowsEnvironment = "OP_ACCOUNT/u";
      signer = "/home/test-user/.local/bin/op-ssh-sign-wsl";
      signerBridge = {
        source = ../../../hosts/x86_64-linux/wsl/op-ssh-sign-wsl;
        executable = true;
      };
    };
  };

  testWslAndNativeLinuxDesktopPackageSelection = {
    expr =
      map
        (
          home:
          let
            contains =
              package: builtins.any (candidate: candidate.drvPath == package.drvPath) home.config.home.packages;
          in
          {
            chrome = contains (configuredChrome home);
            rawChrome = contains home.pkgs.google-chrome;
            spotify = contains home.pkgs.spotify;
            signal = contains home.pkgs.signal-desktop;
            obsidian = contains home.pkgs.obsidian;
            onePassword = contains home.pkgs._1password-gui;
            nautilus = contains home.pkgs.nautilus;
            browser = home.config.home.sessionVariables.BROWSER or null;
          }
        )
        [
          wsl
          linux
        ];
    expected = [
      {
        chrome = true;
        rawChrome = false;
        spotify = true;
        signal = true;
        obsidian = true;
        onePassword = true;
        nautilus = true;
        browser = "${configuredChrome wsl}/bin/google-chrome-stable";
      }
      {
        chrome = false;
        rawChrome = true;
        spotify = false;
        signal = false;
        obsidian = true;
        onePassword = true;
        nautilus = true;
        browser = null;
      }
    ];
  };

  testNautilusIsUnavailableOnDarwin = {
    expr = builtins.any (package: (package.pname or "") == "nautilus") darwin.config.home.packages;
    expected = false;
  };

  testWslChromePackageWrapsJapaneseLocaleAndLanguage = {
    expr = builtins.all (token: wsl.pkgs.lib.hasInfix token (configuredChrome wsl).postFixup) [
      "wrapProgram"
      "--set LANG "
      "--set LC_ALL "
      "--set LANGUAGE "
      "--set GTK_IM_MODULE_FILE "
      "ja_JP.UTF-8"
      "--add-flags"
      "--lang=ja"
    ];
    expected = true;
  };

  testWslChromeBuildsAnExplicitFcitxGtk3ModuleCache = {
    expr =
      let
        inherit (wsl) pkgs;
        markerStart = "__DOTFILES_GTK_CACHE_BEGIN__";
        markerEnd = "__DOTFILES_GTK_CACHE_END__";
        selected = import ../../../modules/browsers/chrome {
          pkgs = pkgs // {
            runCommand =
              name: attrs: script:
              markerStart
              + builtins.toJSON {
                inherit name script;
                nativeBuildInputs = map toString attrs.nativeBuildInputs;
                inherit (attrs) preferLocalBuild allowSubstitutes;
                disallowedReferences = map toString attrs.disallowedReferences;
              }
              + markerEnd;
          };
        };
        pieces = pkgs.lib.splitString markerStart selected.postFixup;
      in
      if builtins.length pieces == 2 then
        builtins.fromJSON (
          builtins.unsafeDiscardStringContext (
            builtins.head (pkgs.lib.splitString markerEnd (builtins.elemAt pieces 1))
          )
        )
      else
        null;
    expected = {
      name = "chrome-fcitx-gtk3-immodules.cache";
      nativeBuildInputs = [ (toString wsl.pkgs.gtk3) ];
      preferLocalBuild = true;
      allowSubstitutes = false;
      disallowedReferences = [ (toString (wsl.pkgs.lib.getDev wsl.pkgs.gtk3)) ];
      script = ''
        gtk-query-immodules-3.0 "${wsl.pkgs.fcitx5-gtk}/lib/gtk-3.0/3.0.0/immodules/im-fcitx5.so" > "$out"
      '';
    };
  };

  testWslDesktopExtrasGuardUnsupportedPlatforms = {
    expr =
      map
        (
          system:
          let
            pkgs = mkPkgs system;
          in
          ((import ../../../modules/desktop.nix).wslDesktop {
            inherit pkgs;
            inherit (pkgs) lib;
          }).home.packages
        )
        [
          "aarch64-linux"
          "aarch64-darwin"
        ];
    expected = [
      [ ]
      [ ]
    ];
  };

  testLinuxDesktopModuleDoesNotInstallAppsOnDarwin = {
    expr =
      let
        pkgs = mkPkgs "aarch64-darwin";
      in
      ((import ../../../modules/desktop.nix).linuxDesktop {
        inherit pkgs;
        inherit (pkgs) lib;
      }).home.packages;
    expected = [ ];
  };

  testWSLHomeModuleExcludesNativeDesktopPackages =
    let
      pkgs = mkPkgs "x86_64-linux";
      tools =
        ((import ../../../modules/tools.nix).homeManager {
          inherit (wsl) config;
          inherit inputs pkgs;
          inherit (pkgs) lib;
        }).home.packages;
      contains = needle: packages: builtins.any (package: package.drvPath == needle.drvPath) packages;
    in
    {
      expr = {
        sharedTools = builtins.all (package: contains package wsl.config.home.packages) tools;
        excludesDiscord = !(contains pkgs.discord wsl.config.home.packages);
        excludesCompositor = !(contains pkgs.hyprland wsl.config.home.packages);
        excludesLauncher = !(contains pkgs.fuzzel wsl.config.home.packages);
      };
      expected = {
        sharedTools = true;
        excludesDiscord = true;
        excludesCompositor = true;
        excludesLauncher = true;
      };
    };

  testDarwinHomeModuleOwnsDarwinSessionVariables = {
    expr = {
      homebrew = darwin.config.home.sessionVariables.HOMEBREW_AUTO_UPDATE_SECS;
      onePassword = darwin.config.home.sessionVariables.OP_BIOMETRIC_UNLOCK_ENABLED;
      homebrewPath = builtins.elem "/opt/homebrew/bin" darwin.config.home.sessionPath;
      terminfo = builtins.match ".*TERMINFO_DIRS.*" darwin.config.programs.zsh.envExtra != null;
    };
    expected = {
      homebrew = "86400";
      onePassword = "true";
      homebrewPath = true;
      terminfo = true;
    };
  };

  testObsidianIsSelectedByPlatformModules = {
    expr = {
      darwin = darwinPackages.contains darwinPackages.pkgs.obsidian darwinPackages.system;
      linux = builtins.any (package: (package.pname or "") == "obsidian") linux.config.home.packages;
      wsl = builtins.any (package: (package.pname or "") == "obsidian") wsl.config.home.packages;
    };
    expected = {
      darwin = true;
      linux = true;
      wsl = true;
    };
  };

  testTerminalKeybindingHelpersHavePlatformScopedPackages = {
    expr = {
      darwinSystem = darwinPackages.contains darwinPackages.pkgs.aerospace darwinPackages.system;
      linuxHome = builtins.any (package: (package.pname or "") == "aerospace") linux.config.home.packages;
      wslHome = builtins.any (package: (package.pname or "") == "aerospace") wsl.config.home.packages;
    };
    expected = {
      darwinSystem = true;
      linuxHome = false;
      wslHome = false;
    };
  };
}
