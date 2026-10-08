{ inputs }:
let
  darwin = inputs.nix-darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    modules = [
      ../../hosts/aarch64-darwin/omarchy-keybindings.nix
      {
        system.primaryUser = "keybinding-test";
        system.stateVersion = 6;
        users.users.keybinding-test.home = "/Users/keybinding-test";
        nixpkgs.pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
      }
    ];
  };
  inherit (darwin) config pkgs;
  inherit (pkgs) lib;
  service = config.services.aerospace;
  keys = service.settings.mode.main.binding;
  agent = config.launchd.user.agents.aerospace;
  catalog = import ../../packages/sets.nix { inherit pkgs lib; };
in
{
  testOmarchyDisabledDoesNotChangeSystemShortcuts = {
    expr =
      let
        disabled = darwin.extendModules {
          modules = [ { services.aerospace.enable = lib.mkForce false; } ];
        };
      in
      {
        activation = disabled.config.system.activationScripts.omarchySymbolicHotkeys.text or "";
        dockOrder = disabled.config.system.defaults.dock.mru-spaces;
        dockGrouping = disabled.config.system.defaults.dock.expose-group-apps;
      };
    expected = {
      activation = "";
      dockOrder = null;
      dockGrouping = null;
    };
  };
  testOmarchyAerospaceIsOwnedByDarwin = {
    expr = {
      enabled = service.enable;
      configVersion = service.settings.config-version;
      catalogPackage = service.package == builtins.head (catalog.resolve [ "aerospace" ]);
      systemPackage = builtins.elem service.package config.environment.systemPackages;
      guiCatalogPackage = builtins.elem service.package catalog.darwinSystemPackages;
      homeDoesNotDuplicateGui = !(builtins.elem service.package catalog.darwinHomePackages);
      launchdOwnsStartup =
        !service.settings.start-at-login && agent.serviceConfig.RunAtLoad && agent.serviceConfig.KeepAlive;
      explicitImmutableConfig = lib.hasInfix "--config-path /nix/store/" agent.command;
    };
    expected = {
      enabled = true;
      configVersion = 2;
      catalogPackage = true;
      systemPackage = true;
      guiCatalogPackage = true;
      homeDoesNotDuplicateGui = true;
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
        script = config.system.activationScripts.omarchySymbolicHotkeys.text;
      in
      {
        scopedUser = lib.hasInfix "--user=keybinding-test" script;
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
      scopedUser = true;
      collisionsDisabled = true;
      noDictionaryReplacement = true;
    };
  };

  testOmarchyPackageDoesNotLeakToLinux = {
    expr =
      builtins.map
        (
          system:
          let
            linuxPkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs system;
            linuxCatalog = import ../../packages/sets.nix {
              pkgs = linuxPkgs;
              inherit lib;
            };
          in
          {
            packages = linuxCatalog.resolve [ "aerospace" ];
            linuxUnsupported = linuxCatalog.supportReport.aerospace.linux.unsupported != "";
            windowsUnsupported = linuxCatalog.supportReport.aerospace.windows.unsupported != "";
            providerErrors = builtins.filter (lib.hasPrefix "aerospace:") linuxCatalog.providerErrors;
          }
        )
        [
          "aarch64-linux"
          "x86_64-linux"
        ];
    expected = builtins.genList (_: {
      packages = [ ];
      linuxUnsupported = true;
      windowsUnsupported = true;
      providerErrors = [ ];
    }) 2;
  };
}
