let
  contains =
    pattern: content:
    builtins.any (line: builtins.match ".*${pattern}.*" line != null) (
      builtins.filter builtins.isString (builtins.split "\n" content)
    );

  flake = builtins.readFile ../../flake.nix;
  apps = builtins.readFile ../flakes/apps.nix;
  hosts = builtins.readFile ../flakes/hosts.nix;
  home = builtins.readFile ../flakes/home.nix;
  hostLib = builtins.readFile ../flakes/lib/hosts.nix;
  systems = builtins.readFile ../flakes/systems.nix;
  treefmt = builtins.readFile ../flakes/treefmt.nix;
in
{
  testFlakePinsPlatformInputs = {
    expr = {
      darwin = contains "nix-darwin" flake;
      homebrew = contains "nix-homebrew" flake;
      systemManager = contains "system-manager" flake;
    };
    expected = {
      darwin = true;
      homebrew = true;
      systemManager = true;
    };
  };

  testFlakeExposesLockedRunnerApps = {
    expr = {
      darwin = contains "darwin-rebuild" apps;
      systemManager = contains "system-manager" apps;
      lockedDarwin = contains "inputs.nix-darwin.packages" apps;
      lockedSystemManager = contains "inputs.system-manager.packages" apps;
    };
    expected = {
      darwin = true;
      systemManager = true;
      lockedDarwin = true;
      lockedSystemManager = true;
    };
  };

  testRunnerAppsKeepPlatformGuards = {
    expr = {
      darwin = contains "pkgs.stdenv.hostPlatform.isDarwin" apps;
      linux = contains "pkgs.stdenv.hostPlatform.isLinux" apps;
    };
    expected = {
      darwin = true;
      linux = true;
    };
  };

  testTreefmtKeepsCheckWithoutDeprecatedPlatformAlias = {
    expr = {
      check = contains "build.check =" treefmt;
      command = contains "treefmt --no-cache" treefmt;
      currentDarwinPredicate = contains "pkgs.stdenv.hostPlatform.isDarwin" treefmt;
      deprecatedDarwinPredicate = contains "pkgs.stdenv.isDarwin" treefmt;
    };
    expected = {
      check = true;
      command = true;
      currentDarwinPredicate = true;
      deprecatedDarwinPredicate = false;
    };
  };

  testNativeNixOSOutputRequiresHardwareProfile = {
    expr = {
      environment = contains "DOTFILES_NIXOS_HARDWARE_CONFIG" hosts;
      guard = contains "optionalAttrs.*hardwareConfig" hosts;
    };
    expected = {
      environment = true;
      guard = true;
    };
  };

  testHomeManagerOutputsSelectCanonicalOSModules = {
    expr = {
      darwin = contains "darwin.nix" home;
      linux = contains "linux.nix" home;
      wsl = contains "homeModulePath" hosts && contains "wsl.nix" hosts;
      nativeLinux = contains "homeModulePath" hosts && contains "linux.nix" hosts;
    };
    expected = {
      darwin = true;
      linux = true;
      wsl = true;
      nativeLinux = true;
    };
  };

  testNixOSHomeManagerUsesSelectedUserAndModule = {
    expr = {
      user = contains "users." hostLib;
      module = contains "homeModulePath" hostLib;
    };
    expected = {
      user = true;
      module = true;
    };
  };

  testSupportedSystemsExcludeIntelDarwin = {
    expr = contains "system != \"x86_64-darwin\"" systems;
    expected = true;
  };
}
