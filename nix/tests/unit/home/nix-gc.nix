{
  inputs,
  homeConfigurations ? import ../../fixtures/home-configurations.nix { inherit inputs; },
}:
let
  inherit (homeConfigurations) homes lib;
  darwinLib = import "${inputs.home-manager}/modules/lib/darwin.nix" { inherit lib; };
in
{
  testStandaloneHomesUseDeclaredGarbageCollectionSettings = {
    expr = map (home: {
      automatic = home.config.nix.gc.automatic;
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
        automatic = true;
        integration =
          if home.pkgs.stdenv.hostPlatform.isDarwin then
            {
              enable = true;
              schedule = darwinLib.mkCalendarInterval (builtins.head cfg.dates);
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
}
