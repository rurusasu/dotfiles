{ inputs }:
let
  fixtures = import ../../fixtures/packages.nix { inherit inputs; };
  mkPkgs = system: fixtures.mkPkgs system;

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

  darwinPackageSets =
    let
      system = "aarch64-darwin";
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      sets = import ../../../packages/sets.nix {
        inherit pkgs;
        inherit (pkgs) lib;
        codexPackage = pkgs.hello;
      };
      contains = package: packages: builtins.elem package packages;
    in
    {
      inherit sets;
      inherit (pkgs) obsidian;
      inherit contains;
    };
in
{
  testCodexConfigurationIsOwnedByHomeManagerAcrossHomes = {
    expr =
      map
        (home: {
          enabled = home.config.programs.codex.enable;
          npmProvider = home.config.programs.codex.package == null;
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
      npmProvider = true;
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

  testDshModuleUsesUpstreamPackageOnce = {
    expr =
      map
        (
          home:
          let
            package = inputs.llm-agents.packages.${home.pkgs.stdenv.hostPlatform.system}.dsh;
          in
          {
            copies = builtins.length (
              builtins.filter (candidate: candidate.drvPath == package.drvPath) home.config.home.packages
            );
          }
        )
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      copies = 1;
    }) 3;
  };

  testPnpmIsInstalledOnceWithNativeHomeManagerSettings = {
    expr =
      map
        (home: {
          enabled = home.config.programs.pnpm.enable;
          package = home.config.programs.pnpm.package.drvPath == home.pkgs.pnpm.drvPath;
          packageCopies = builtins.length (
            builtins.filter (package: package.drvPath == home.pkgs.pnpm.drvPath) home.config.home.packages
          );
          home = home.config.programs.pnpm.pnpmHome;
          environment = home.config.home.sessionVariables.PNPM_HOME;
          binCopies = builtins.length (
            builtins.filter (
              path: path == "${home.config.programs.pnpm.pnpmHome}/bin"
            ) home.config.home.sessionPath
          );
        })
        [
          linux
          wsl
          darwin
        ];
    expected = builtins.genList (_: {
      enabled = true;
      package = true;
      packageCopies = 1;
      home = "/home/test-user/.local/share/pnpm";
      environment = "/home/test-user/.local/share/pnpm";
      binCopies = 1;
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
      gtrAlias = ''!f() { [ -z "$1" ] && echo 'Usage: git gtr <branch>' && return 1; root=$(git worktree list --porcelain | grep '^worktree ' | head -1 | sed 's/^worktree //'); git worktree add "$root/.worktrees/$1" "$1"; }; f'';
    }) 3;
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

  testOnePasswordPackagesAndGitSshPlatformIntegration = {
    expr =
      map
        (home: {
          cliCopies = builtins.length (
            builtins.filter (
              package: package.drvPath == home.pkgs._1password-cli.drvPath
            ) home.config.home.packages
          );
          desktopCopies = builtins.length (
            builtins.filter (
              package: package.drvPath == home.pkgs._1password-gui.drvPath
            ) home.config.home.packages
          );
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
        cliCopies = 1;
        desktopCopies = 1;
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
        cliCopies = 1;
        desktopCopies = 1;
        signer = "/home/test-user/.local/bin/op-ssh-sign-wsl";
        ghqRoot = [
          "/mnt/d/my_programing"
          "/mnt/d/ruru"
        ];
        agent = ''"/home/test-user/.1password/agent.sock"'';
        agentEnvironment = "/home/test-user/.1password/agent.sock";
        opensshAgentEnabled = false;
        gpgSshAgentEnabled = false;
        publicKeyActivationAfter = [ "writeBoundary" ];
        publicKeyIsStoreManaged = false;
      }
      {
        cliCopies = 1;
        desktopCopies = 0;
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

  testFdStarshipAndPatinaAreAvailableAcrossHomes = {
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
            copies =
              name:
              builtins.length (
                builtins.filter (package: (package.pname or "") == name) home.config.home.packages
              );
          in
          {
            fdCopies = copies "fd";
            fdFindAlias = home.config.programs.zsh.shellAliases.find;
            patinaCopies = copies "zsh-patina";
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
      fdCopies = 1;
      fdFindAlias = "fd";
      patinaCopies = 1;
      starshipEnabled = true;
      starshipZshIntegration = true;
      starshipInit = true;
      patinaLast = true;
    }) 3;
  };

  testBatAndRipgrepAreEnabledAndInstalledOnceAcrossHomes = {
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
          packageCopies =
            map
              (
                name:
                builtins.length (builtins.filter (package: (package.pname or "") == name) home.config.home.packages)
              )
              [
                "bat"
                "ripgrep"
              ];
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
      packageCopies = [
        1
        1
      ];
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
          packageCopies = builtins.length (
            builtins.filter (package: (package.pname or "") == "eza") home.config.home.packages
          );
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
      packageCopies = 1;
    }) 3;
  };

  testFzfIsInstalledOnceWithSharedDefaultsAcrossHomes = {
    expr =
      map
        (home: {
          enabled = home.config.programs.fzf.enable;
          packageCopies = builtins.length (
            builtins.filter (
              package: package.drvPath == home.config.programs.fzf.package.drvPath
            ) home.config.home.packages
          );
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
      packageCopies = 1;
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

  testZoxideIsInstalledOnceWithShellIntegrationsAcrossHomes = {
    expr =
      map
        (home: {
          enabled = home.config.programs.zoxide.enable;
          packageCopies = builtins.length (
            builtins.filter (
              package: package.drvPath == home.config.programs.zoxide.package.drvPath
            ) home.config.home.packages
          );
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
      packageCopies = 1;
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
            fzfInit = hasInfix (builtins.unsafeDiscardStringContext "source <(${getExe programs.fzf.package} --zsh)") programs.zsh.initContent;
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
            copies = target: builtins.filter (package: package.drvPath == target.drvPath) packages;
            priority = target: (builtins.head (copies target)).meta.priority or 5;
          in
          {
            rustupCopies = builtins.length (copies home.pkgs.rustup);
            analyzerCopies = builtins.length (copies home.pkgs.rust-analyzer);
            formatterCopies = builtins.length (copies home.pkgs.rustfmt);
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
      rustupCopies = 1;
      analyzerCopies = 1;
      formatterCopies = 1;
      analyzerWins = true;
      formatterWins = true;
    }) 3;
  };

  testNeovimHomeManagerOwnership = {
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
            packageCopies = builtins.length (
              builtins.filter (package: package.drvPath == cfg.finalPackage.drvPath) home.config.home.packages
            );
            basePackageInstalled = builtins.any (
              package: package.drvPath == home.pkgs.neovim.drvPath
            ) home.config.home.packages;
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
                  home.pkgs.typescript-language-server
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
      packageCopies = 1;
      basePackageInstalled = false;
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
              "nautilus"
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
              "source ${../../../home/shells/zsh/plugins.zsh}"
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
        "source ${../../../home/shells/zsh/plugins.zsh}"
        "source ${../../../home/shells/zsh/prompt.zsh}"
      ];
    }) 3;
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
      zoxideExclusion = wsl.config.home.sessionVariables._ZO_EXCLUDE_DIRS;
    };
    expected = {
      browser = "explorer.exe";
      inputMethod = "fcitx";
      zoxideExclusion = "/mnt/wsl/*:/mnt/wslg/*";
    };
  };

  testWSLHomeModuleExcludesNativeDesktopPackages =
    let
      pkgs = mkPkgs "x86_64-linux";
      sets = import ../../../packages/sets.nix {
        inherit pkgs;
        inherit (pkgs) lib;
        codexPackage = pkgs.hello;
      };
      catalogDrvPaths = builtins.map (package: package.drvPath) sets.all;
      selectedCatalogDrvPaths = builtins.sort builtins.lessThan (
        pkgs.lib.unique (
          builtins.filter (drvPath: builtins.elem drvPath catalogDrvPaths) (
            builtins.map (package: package.drvPath) wsl.config.home.packages
          )
        )
      );
      expectedCatalogDrvPaths = builtins.sort builtins.lessThan (
        pkgs.lib.unique (
          builtins.map (package: package.drvPath) (sets.allWithout sets.nativeDesktopPackageNames)
        )
      );
      containsDrvPath =
        needle: packages: builtins.any (package: package.drvPath == needle.drvPath) packages;
    in
    {
      expr = {
        inherit selectedCatalogDrvPaths;
        excludesDiscord = !(containsDrvPath pkgs.discord wsl.config.home.packages);
      };
      expected = {
        selectedCatalogDrvPaths = expectedCatalogDrvPaths;
        excludesDiscord = true;
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

  testObsidianDeclaresCrossPlatformProviders = {
    expr = {
      windows = darwinPackageSets.sets.supportReport.obsidian.windows;
      darwin = darwinPackageSets.sets.supportReport.obsidian.darwin;
      linux = darwinPackageSets.sets.supportReport.obsidian.linux;
    };
    expected = {
      windows = {
        provider = "winget";
        source = "winget";
        identity = "Obsidian.Obsidian";
      };
      darwin = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "obsidian";
        identity = {
          appName = "Obsidian.app";
        };
      };
      linux = {
        provider = "nix";
        source = "nixpkgs";
        nixAttr = "obsidian";
        identity = "obsidian";
      };
    };
  };

  testObsidianDarwinGuiUsesSystemPackage = {
    expr = {
      system = darwinPackageSets.contains darwinPackageSets.obsidian darwinPackageSets.sets.darwinSystemPackages;
      home = darwinPackageSets.contains darwinPackageSets.obsidian darwinPackageSets.sets.darwinHomePackages;
    };
    expected = {
      system = true;
      home = false;
    };
  };

  testTerminalKeybindingHelpersHavePlatformScopedProviders =
    let
      report = darwinPackageSets.sets.supportReport;
    in
    {
      expr = {
        aerospace = {
          inTerminal = builtins.any (
            package: (package.pname or null) == "aerospace"
          ) darwinPackageSets.sets.terminal;
          darwin = {
            provider = report.aerospace.darwin.provider;
            source = report.aerospace.darwin.source;
            appName = report.aerospace.darwin.identity.appName;
          };
          linuxUnsupported = report.aerospace.linux.unsupported;
          windowsUnsupported = report.aerospace.windows.unsupported;
        };
      };
      expected = {
        aerospace = {
          inTerminal = true;
          darwin = {
            provider = "nix";
            source = "nixpkgs";
            appName = "AeroSpace.app";
          };
          linuxUnsupported = "AeroSpace is only available on macOS";
          windowsUnsupported = "AeroSpace is only available on macOS";
        };
      };
    };
}
