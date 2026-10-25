{ inputs, ... }:
let
  lib = inputs.nixpkgs.lib;
  # Preserve the production registration and module lists, overriding only
  # process-derived Darwin identity for deterministic sandbox evaluation.
  registered = import ../../../hosts/configurations.nix {
    inputs = inputs // {
      nix-darwin = inputs.nix-darwin // {
        lib = inputs.nix-darwin.lib // {
          darwinSystem =
            args:
            inputs.nix-darwin.lib.darwinSystem (
              args
              // {
                specialArgs = (args.specialArgs or { }) // {
                  sudoUser = "test-user";
                  currentUser = "test-user";
                };
              }
            );
        };
      };
    };
  };
  homes = map (system: registered.homeConfigurations.${system}) [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
  ];
  nixos = registered.nixosConfigurations.nixos;
  darwin = registered.darwinConfigurations.macos;
  darwinHome = darwin.config.home-manager.users.${darwin.config.system.primaryUser};
  declarations = {
    common = import ../../../home/common.nix {
      inherit lib;
      config = { };
    };
    nixos = import ../../../hosts/nixos.nix {
      inherit inputs lib;
      pkgs = { };
    };
    darwin = import ../../../hosts/darwin.nix {
      inherit inputs lib;
      pkgs = { };
      sudoUser = "test-user";
      currentUser = "test-user";
    };
  };
in
{
  testHostRegistrationsOwnGarbageCollectionDeclarations = {
    expr = {
      gc = lib.mapAttrs (_: module: lib.hasAttrByPath [ "nix" "gc" ] module) declarations;
      darwinMinFree = lib.hasAttrByPath [ "nix" "settings" "min-free" ] declarations.darwin;
    };
    expected = {
      gc = {
        common = false;
        nixos = false;
        darwin = false;
      };
      darwinMinFree = false;
    };
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
        nixPackage =
          if home.config.nix.enable && home.config.nix.package != null then
            home.config.nix.package
          else
            home.pkgs.nix;
      in
      {
        integration =
          if home.pkgs.stdenv.hostPlatform.isDarwin then
            {
              enable = true;
              schedule =
                (import "${inputs.home-manager}/modules/lib/darwin.nix" { inherit lib; }).mkCalendarInterval
                  (builtins.head cfg.dates);
              command = [
                "${nixPackage}/bin/nix-collect-garbage"
              ]
              ++ lib.optional (cfg.options != null) cfg.options;
            }
          else
            {
              schedule = cfg.dates;
              command = [
                (toString (
                  home.pkgs.writeShellScript "nix-gc" "exec ${nixPackage}/bin/nix-collect-garbage ${
                    lib.optionalString (cfg.options != null) cfg.options
                  }"
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
          users = lib.mapAttrsToList (_: home: {
            integrated = home.submoduleSupport.enable;
            automatic = home.nix.gc.automatic;
            userService = builtins.hasAttr "nix-gc" home.systemd.user.services;
            userTimer = builtins.hasAttr "nix-gc" home.systemd.user.timers;
            userAgent = builtins.hasAttr "nix-gc" home.launchd.agents;
          }) host.config.home-manager.users;
        })
        [
          nixos
          darwin
        ];
    expected =
      map
        (_: {
          automatic = true;
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
        commandUsesOptions =
          nixos.config.nix.gc.options != ""
          && lib.hasInfix nixos.config.nix.gc.options nixos.config.systemd.services.nix-gc.script;
      };
      darwin = {
        schedule = darwin.config.launchd.daemons.nix-gc.serviceConfig.StartCalendarInterval;
        commandTargetsNix = lib.hasInfix (builtins.unsafeDiscardStringContext "${darwin.config.nix.package}/bin/nix-collect-garbage") darwin.config.launchd.daemons.nix-gc.command;
        commandUsesOptions =
          darwin.config.nix.gc.options != ""
          && lib.hasInfix darwin.config.nix.gc.options darwin.config.launchd.daemons.nix-gc.command;
        runAtLoad = darwin.config.launchd.daemons.nix-gc.serviceConfig.RunAtLoad;
      };
    };
    expected = {
      nixos = {
        schedule = nixos.config.nix.gc.dates;
        delay = nixos.config.nix.gc.randomizedDelaySec;
        persistent = nixos.config.nix.gc.persistent;
        commandTargetsNix = true;
        commandUsesOptions = true;
      };
      darwin = {
        schedule = darwin.config.nix.gc.interval;
        commandTargetsNix = true;
        commandUsesOptions = true;
        runAtLoad = false;
      };
    };
  };

  testRegisteredDarwinPreservesCacheScheduleAndGarbageCollectionPressureSettings = {
    expr = {
      cacheMaintenance = darwinHome.launchd.agents.tool-cache-maintenance.enable;
      cacheSchedule = darwinHome.launchd.agents.tool-cache-maintenance.config.StartCalendarInterval;
      cacheRunsOnActivation = darwinHome.launchd.agents.tool-cache-maintenance.config.RunAtLoad;
      minFreeDeclared = darwin.config.nix.settings ? min-free;
      minFreePositive = darwin.config.nix.settings.min-free > 0;
      minFreeInDaemonConfig =
        lib.hasInfix "min-free = ${toString darwin.config.nix.settings.min-free}"
          darwin.config.environment.etc."nix/nix.conf".source.text;
      maxFreeDeclared = darwin.config.nix.settings ? max-free;
    };
    expected = {
      cacheMaintenance = true;
      cacheSchedule = darwin.config.nix.gc.interval;
      cacheRunsOnActivation = false;
      minFreeDeclared = true;
      minFreePositive = true;
      minFreeInDaemonConfig = true;
      maxFreeDeclared = false;
    };
  };
}
