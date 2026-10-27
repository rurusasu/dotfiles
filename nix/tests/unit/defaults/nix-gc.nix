{
  inputs,
  code,
  upstream,
}:
let
  lib = inputs.nixpkgs.lib;
  registered = (code.nix.defaults inputs).configurations;
  homes = map (system: registered.homeConfigurations.${system}) [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
  ];
  nixos = registered.nixosConfigurations.nixos;
  native = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {
      inherit inputs;
      platform = "linux";
    };
    modules = [ (code.nix.defaults inputs).systemDefaults ];
  };
  darwin = registered.darwinConfigurations.macos;
  darwinHome = darwin.config.home-manager.users.${darwin.config.system.primaryUser};

in
{
  testStandaloneHomesInstallStableLixAndUseItForGarbageCollection = {
    expr = map (home: {
      selected = home.config.nix.package == home.pkgs.lixPackageSets.stable.lix;
      installed = builtins.elem home.pkgs.lixPackageSets.stable.lix home.config.home.packages;
    }) homes;
    expected = map (_: {
      selected = true;
      installed = true;
    }) homes;
  };

  testRegisteredStandaloneHomesUseNativeUserGarbageCollection = {
    expr = map (home: {
      automatic = home.config.nix.gc.automatic;
      systemd = home.config.systemd.user.enable;
      launchd = home.config.launchd.enable;
      integrated = home.config.submoduleSupport.enable;
    }) homes;
    expected = [
      {
        automatic = true;
        systemd = true;
        launchd = false;
        integrated = false;
      }
      {
        automatic = true;
        systemd = true;
        launchd = false;
        integrated = false;
      }
      {
        automatic = true;
        systemd = false;
        launchd = true;
        integrated = false;
      }
    ];
  };

  testStandaloneHomesUseDeclaredGarbageCollectionSettings = {
    expr = map (home: {
      dates = home.config.nix.gc.dates;
      integration =
        if home.pkgs.stdenv.hostPlatform.isDarwin then
          let
            agent = home.config.launchd.agents.nix-gc;
          in
          {
            inherit (agent) enable;
            schedule = map (lib.filterAttrs (_: value: value != null)) agent.config.StartCalendarInterval;
            command = agent.config.ProgramArguments;
          }
        else
          let
            timer = home.config.systemd.user.timers.nix-gc.Timer;
          in
          {
            schedule = timer.OnCalendar;
            command = map toString home.config.systemd.user.services.nix-gc.Service.ExecStart;
            delay = timer.RandomizedDelaySec;
            persistent = timer.Persistent;
            target = timer.Unit;
          };
    }) homes;
    expected = map (
      home:
      let
        cfg = home.config.nix.gc;
        nixPackage = home.config.nix.package;
      in
      {
        dates = [ "daily" ];
        integration =
          if home.pkgs.stdenv.hostPlatform.isDarwin then
            {
              enable = true;
              schedule = (upstream.home-manager.code.modules.lib.darwin { inherit lib; }).mkCalendarInterval (
                builtins.head cfg.dates
              );
              command = [
                "${nixPackage}/bin/nix-collect-garbage"
                cfg.options
              ];
            }
          else
            {
              schedule = cfg.dates;
              command = [
                (toString (
                  home.pkgs.writeShellScript "nix-gc" "exec ${nixPackage}/bin/nix-collect-garbage ${cfg.options}"
                ))
              ];
              delay = cfg.randomizedDelaySec;
              inherit (cfg) persistent;
              target = "nix-gc.service";
            };
      }
    ) homes;
  };

  testRegisteredIntegratedSystemsUseSystemGarbageCollection = {
    expr =
      map
        (host: {
          automatic = host.config.nix.gc.automatic;
          timeZone = host.config.time.timeZone;
          minFree = host.config.nix.settings.min-free;
          backupFileExtension = host.config.home-manager.backupFileExtension;
          users = lib.mapAttrsToList (_: home: {
            integrated = home.submoduleSupport.enable;
            automatic = home.nix.gc.automatic;
            userService = builtins.hasAttr "nix-gc" home.systemd.user.services;
            userTimer = builtins.hasAttr "nix-gc" home.systemd.user.timers;
            userAgent = builtins.hasAttr "nix-gc" home.launchd.agents;
          }) host.config.home-manager.users;
        })
        [
          native
          nixos
          darwin
        ];
    expected =
      map
        (_: {
          automatic = true;
          timeZone = "Asia/Tokyo";
          minFree = 10 * 1024 * 1024 * 1024;
          backupFileExtension = "hm-backup";
          users = [
            {
              integrated = true;
              automatic = false;
              userService = false;
              userTimer = false;
              userAgent = false;
            }
          ];
        })
        [
          native
          nixos
          darwin
        ];
  };

  testRegisteredSystemsGenerateGarbageCollectionArtifactsFromEffectiveSettings = {
    expr = {
      nixos = {
        schedule = nixos.config.systemd.services.nix-gc.startAt;
        delay = nixos.config.systemd.timers.nix-gc.timerConfig.RandomizedDelaySec;
        persistent = nixos.config.systemd.timers.nix-gc.timerConfig.Persistent;
        commandTargetsNix = lib.hasInfix (builtins.unsafeDiscardStringContext "${nixos.config.nix.package.out}/bin/nix-collect-garbage") nixos.config.systemd.services.nix-gc.script;
        options = nixos.config.nix.gc.options;
        commandUsesOptions = lib.hasInfix nixos.config.nix.gc.options nixos.config.systemd.services.nix-gc.script;
      };
      darwin = {
        schedule = map (lib.filterAttrs (
          _: value: value != null
        )) darwin.config.launchd.daemons.nix-gc.serviceConfig.StartCalendarInterval;
        commandTargetsNix = lib.hasInfix (builtins.unsafeDiscardStringContext "${darwin.config.nix.package}/bin/nix-collect-garbage") darwin.config.launchd.daemons.nix-gc.command;
        options = darwin.config.nix.gc.options;
        commandUsesOptions = lib.hasInfix darwin.config.nix.gc.options darwin.config.launchd.daemons.nix-gc.command;
        runAtLoad = darwin.config.launchd.daemons.nix-gc.serviceConfig.RunAtLoad;
      };
    };
    expected = {
      nixos = {
        schedule = [ "03:15" ];
        delay = nixos.config.nix.gc.randomizedDelaySec;
        persistent = nixos.config.nix.gc.persistent;
        commandTargetsNix = true;
        commandUsesOptions = true;
        options = "--delete-old";
      };
      darwin = {
        schedule = [
          {
            Hour = 3;
            Minute = 15;
          }
        ];
        commandTargetsNix = true;
        commandUsesOptions = true;
        options = "--delete-old";
        runAtLoad = false;
      };
    };
  };

  testDarwinUsesNixGarbageCollectionWithoutApplicationCacheJob = {
    expr = {
      customCacheJob = darwinHome.launchd.agents ? tool-cache-maintenance;
      customLogDirectory = darwinHome.home.activation ? cacheMaintenanceLogDirectory;
      minFreeDeclared = darwin.config.nix.settings ? min-free;
      minFreePositive = darwin.config.nix.settings.min-free > 0;
      minFreeInDaemonConfig =
        lib.hasInfix "min-free = ${toString darwin.config.nix.settings.min-free}"
          darwin.config.environment.etc."nix/nix.conf".source.text;
      maxFreeDeclared = darwin.config.nix.settings ? max-free;
    };
    expected = {
      customCacheJob = false;
      customLogDirectory = false;
      minFreeDeclared = true;
      minFreePositive = true;
      minFreeInDaemonConfig = true;
      maxFreeDeclared = false;
    };
  };
}
