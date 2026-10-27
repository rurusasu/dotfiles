{ inputs }:
let
  home = (import ../../../fixtures/packages.nix { inherit inputs; }).mkHome "aarch64-darwin" [
    { programs.aerospace.enable = true; }
  ];
  inherit (home) config pkgs;
  inherit (pkgs) lib;
  service = config.programs.aerospace;
  keys = service.settings.mode.main.binding;
  agent = config.launchd.agents.aerospace;
in
{
  testOmarchyDisabledDoesNotChangeSystemShortcuts = {
    expr =
      let
        disabled = home.extendModules {
          modules = [ { programs.aerospace.enable = lib.mkForce false; } ];
        };
      in
      {
        activation = disabled.config.home.activation.omarchySymbolicHotkeys.data or "";
        legacyActivation = disabled.config.home.activation.retireNixDarwinAerospace.data or "";
        dockOrder = disabled.config.targets.darwin.defaults."com.apple.dock".mru-spaces or null;
        dockGrouping = disabled.config.targets.darwin.defaults."com.apple.dock".expose-group-apps;
      };
    expected = {
      activation = "";
      legacyActivation = "";
      dockOrder = null;
      dockGrouping = null;
    };
  };
  testOmarchyAerospaceIsOwnedByHomeManager = {
    expr = {
      enabled = service.enable;
      configVersion = service.settings.config-version;
      selectedPackage = service.package == pkgs.aerospace;
      homePackage = builtins.elem service.package config.home.packages;
      launchdOwnsStartup =
        !service.settings.start-at-login && agent.config.RunAtLoad && agent.config.KeepAlive;
      explicitImmutableConfig =
        builtins.elemAt agent.config.ProgramArguments 1 == "--config-path"
        && lib.hasPrefix "/nix/store/" (builtins.elemAt agent.config.ProgramArguments 2);
    };
    expected = {
      enabled = true;
      configVersion = 2;
      selectedPackage = true;
      homePackage = true;
      launchdOwnsStartup = true;
      explicitImmutableConfig = true;
    };
  };

  testOmarchyOverridesConflictingCommandBindings = {
    expr = lib.getAttrs [ "cmd-f" "cmd-t" "cmd-q" "cmd-w" "cmd-s" ] keys;
    expected = {
      cmd-f = "fullscreen";
      cmd-t = "layout floating tiling";
      cmd-q = "close";
      cmd-w = "close";
      cmd-s = "workspace --auto-back-and-forth scratchpad";
    };
  };

  testOmarchyWorkspaceCycleUsesGeneratedHelpers = {
    expr = {
      next =
        lib.hasPrefix "exec-and-forget /nix/store/" keys.cmd-tab
        && lib.hasSuffix "-omarchy-workspace-next" keys.cmd-tab;
      prev =
        lib.hasPrefix "exec-and-forget /nix/store/" keys.cmd-shift-tab
        && lib.hasSuffix "-omarchy-workspace-prev" keys.cmd-shift-tab;
    };
    expected = {
      next = true;
      prev = true;
    };
  };

  testOmarchyAllTenWorkspaceTransfersFollowUnlessSilent = {
    expr = builtins.all (
      number:
      let
        workspace = toString number;
        key = if number == 10 then "0" else workspace;
      in
      keys."cmd-${key}" == "workspace ${workspace}"
      && keys."cmd-shift-${key}" == "move-node-to-workspace --focus-follows-window ${workspace}"
      && keys."cmd-shift-alt-${key}" == "move-node-to-workspace ${workspace}"
      && builtins.elem workspace service.settings.persistent-workspaces
    ) (lib.range 1 10);
    expected = true;
  };

  testOmarchyRecoveryModeCanReturnToMain = {
    expr = {
      enter = keys.cmd-ctrl-alt-esc;
      exit = service.settings.mode.passthrough.binding.cmd-ctrl-alt-esc;
      passthroughOnlyBindsRecovery = builtins.attrNames service.settings.mode.passthrough.binding;
      clipboardUsesNativeCommandKeys = builtins.all (key: !(builtins.hasAttr key keys)) [
        "cmd-c"
        "cmd-v"
        "cmd-x"
      ];
    };
    expected = {
      enter = "mode passthrough";
      exit = "mode main";
      passthroughOnlyBindsRecovery = [ "cmd-ctrl-alt-esc" ];
      clipboardUsesNativeCommandKeys = true;
    };
  };

  testOmarchySymbolicShortcutUpdatesPreserveOtherKeys = {
    expr =
      let
        script = config.home.activation.omarchySymbolicHotkeys.data;
      in
      {
        userActivation = !(lib.hasInfix "sudo" script) && !(lib.hasInfix "launchctl asuser" script);
        collisionsDisabled = builtins.all (id: lib.hasInfix "-dict-add ${id} " script) [
          "27"
          "28"
          "29"
          "30"
          "31"
          "64"
          "65"
          "184"
        ];
        noDictionaryReplacement = !(lib.hasInfix "-dict " script);
      };
    expected = {
      userActivation = true;
      collisionsDisabled = true;
      noDictionaryReplacement = true;
    };
  };

  testOmarchyPackageDoesNotLeakToLinux = {
    expr =
      map
        (
          system:
          let
            fixtures = import ../../../fixtures/packages.nix { inherit inputs; };
          in
          {
            linuxPackage =
              builtins.any (package: (package.pname or "") == "aerospace")
                (fixtures.mkHome system [
                  (fixtures.homeModule "linux")
                ]).config.home.packages;
            windowsPackage = fixtures.windowsPackages ? "aerospace";
          }
        )
        [
          "aarch64-linux"
          "x86_64-linux"
        ];
    expected = builtins.genList (_: {
      linuxPackage = false;
      windowsPackage = false;
    }) 2;
  };
}
