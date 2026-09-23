let
  lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
  rootInputs = lock.nodes.${lock.root}.inputs;

  platformInputs = [
    {
      name = "nix-darwin";
      owner = "nix-darwin";
      repo = "nix-darwin";
    }
    {
      name = "nix-homebrew";
      owner = "zhaofengli";
      repo = "nix-homebrew";
    }
    {
      name = "system-manager";
      owner = "numtide";
      repo = "system-manager";
    }
  ];

  inspectLockedInput = spec:
    let
      node = lock.nodes.${rootInputs.${spec.name}};
    in
    {
      inherit (node.locked) owner repo type;
      rootInputIsPresent = builtins.hasAttr spec.name rootInputs;
      sourceMatches = node.locked.owner == spec.owner && node.locked.repo == spec.repo;
      hasLockedRevision = node.locked.rev != "";
      hasNarHash = node.locked.narHash != "";
    };

  mkApps =
    {
      system,
      isDarwin,
      isLinux,
    }:
    (import ../flakes/apps.nix {
      inputs = {
        nix-darwin.packages.${system}.darwin-rebuild.executable = "darwin-rebuild";
        system-manager.packages.${system}.default.executable = "system-manager";
      };
    }).perSystem {
      inherit system;
      pkgs.stdenv.hostPlatform = {
        inherit isDarwin isLinux;
      };
      lib = {
        getExe = package: package.executable;
        getExe' = package: binary: "${package.executable}/${binary}";
        optionalAttrs = condition: attrs: if condition then attrs else { };
      };
    };

  darwinApps = mkApps {
    system = "aarch64-darwin";
    isDarwin = true;
    isLinux = false;
  };
  linuxApps = mkApps {
    system = "x86_64-linux";
    isDarwin = false;
    isLinux = true;
  };
  unsupportedApps = mkApps {
    system = "x86_64-freebsd";
    isDarwin = false;
    isLinux = false;
  };

  nixpkgsFixture = builtins.toFile "flake-outputs-nixpkgs-fixture.nix" ''
    { system, ... }:
    {
      stdenv.hostPlatform.system = system;
    }
  '';
  homeInputs = {
    nixpkgs = {
      outPath = nixpkgsFixture;
      lib.optionals = condition: values: if condition then values else [ ];
    };
    workmux.packages = { };
    home-manager.lib.homeManagerConfiguration = args: args;
  };
  homeOutputs = (import ../flakes/home.nix { inputs = homeInputs; }).flake.homeConfigurations;
  processUser = builtins.getEnv "DOTFILES_USER";
  expectedProcessUser = if processUser == "" then "nixos" else processUser;
  processHardwareConfig = builtins.getEnv "DOTFILES_NIXOS_HARDWARE_CONFIG";
  processRequestedSystem = builtins.getEnv "DOTFILES_SYSTEM";

  treefmtModule = (import ../flakes/treefmt.nix { config = { }; }).perSystem {
    config.treefmt.build = {
      devShell.nativeBuildInputs = [ ];
      wrapper = "treefmt-wrapper";
    };
    pkgs = {
      stdenv.hostPlatform.isDarwin = true;
      git = "git";
      git-lfs = "git-lfs";
      mkShell = attrs: attrs;
      runCommandLocal = name: attrs: script: {
        inherit name attrs script;
      };
    };
  };
  treefmtCheck = treefmtModule.treefmt.build.check "/source";
  hasScriptLine = pattern: script: builtins.any (
    line: builtins.match pattern line != null
  ) (builtins.filter builtins.isString (builtins.split "\n" script));

  # Capture constructor arguments to assert generated wiring without claiming
  # evaluation of the complete NixOS module graph.
  hostLib = import ../flakes/lib/hosts.nix {
    inputs = {
      nixpkgs.lib.nixosSystem = args: args;
      home-manager.nixosModules.home-manager = "home-manager-module";
    };
  };
  wslNixosArguments = {
    system = "x86_64-linux";
    hostPath = ../hosts/wsl;
    siteLib = { };
    homeModulePath = ../home/wsl.nix;
  };
  nixosArguments = hostLib.mkNixos wslNixosArguments;
  customUserNixosArguments = hostLib.mkNixos (
    wslNixosArguments // { configuredUser = "alice"; }
  );
  findHomeManagerModule = arguments: builtins.head (
    builtins.filter (
      module: builtins.isAttrs module && module ? "home-manager"
    ) arguments.modules
  );
  homeManagerModule = findHomeManagerModule nixosArguments;
  customUserHomeManagerModule = findHomeManagerModule customUserNixosArguments;
  defaultHomeManagerUser = homeManagerModule."home-manager".users.${expectedProcessUser};
  customHomeManagerUser = customUserHomeManagerModule."home-manager".users.alice;

  hostSpecsFromEnvironment = hostLib.mkNixosHostSpecs { };
  hostSpecsWithEnvironmentValues = hostLib.mkNixosHostSpecs {
    hardwareConfig = processHardwareConfig;
    requestedSystem = processRequestedSystem;
  };
  hostSpecsWithoutHardware = hostLib.mkNixosHostSpecs {
    hardwareConfig = "";
    requestedSystem = "";
  };
  hostSpecsWithHardware = hostLib.mkNixosHostSpecs {
    hardwareConfig = "/etc/nixos/hardware-configuration.nix";
    requestedSystem = "";
  };
  hostSpecsWithRequestedSystem = hostLib.mkNixosHostSpecs {
    hardwareConfig = "/etc/nixos/hardware-configuration.nix";
    requestedSystem = "aarch64-linux";
  };

  supportedSystems = (import ../flakes/systems.nix {
    inputs.systems = [
      "aarch64-darwin"
      "x86_64-darwin"
      "x86_64-linux"
      "aarch64-linux"
    ];
  }).systems;

in
{
  testFlakeLockPinsPlatformInputs = {
    expr = builtins.map inspectLockedInput platformInputs;
    expected = [
      {
        type = "github";
        owner = "nix-darwin";
        repo = "nix-darwin";
        rootInputIsPresent = true;
        sourceMatches = true;
        hasLockedRevision = true;
        hasNarHash = true;
      }
      {
        type = "github";
        owner = "zhaofengli";
        repo = "nix-homebrew";
        rootInputIsPresent = true;
        sourceMatches = true;
        hasLockedRevision = true;
        hasNarHash = true;
      }
      {
        type = "github";
        owner = "numtide";
        repo = "system-manager";
        rootInputIsPresent = true;
        sourceMatches = true;
        hasLockedRevision = true;
        hasNarHash = true;
      }
    ];
  };

  testFlakeLockPlatformInputsFollowRootNixpkgs = {
    expr = {
      darwin = lock.nodes.${rootInputs."nix-darwin"}.inputs.nixpkgs;
      systemManager = lock.nodes.${rootInputs."system-manager"}.inputs.nixpkgs;
    };
    expected = {
      darwin = [ "nixpkgs" ];
      systemManager = [ "nixpkgs" ];
    };
  };

  testRunnerAppsEvaluateForTheirSupportedPlatforms = {
    expr = {
      darwin = darwinApps.apps.darwin-rebuild.program;
      linux = linuxApps.apps.system-manager.program;
      darwinOmitsLinuxRunner = !(darwinApps.apps ? system-manager);
      linuxOmitsDarwinRunner = !(linuxApps.apps ? darwin-rebuild);
      unsupportedPlatformHasNoRunnerApps = unsupportedApps.apps == { };
    };
    expected = {
      darwin = "darwin-rebuild";
      linux = "system-manager/system-manager";
      darwinOmitsLinuxRunner = true;
      linuxOmitsDarwinRunner = true;
      unsupportedPlatformHasNoRunnerApps = true;
    };
  };

  testTreefmtCheckEvaluatesWithHostPlatformLocale = {
    expr = {
      checkName = treefmtCheck.name;
      hasNoCacheCommand = hasScriptLine ".*treefmt --no-cache.*" treefmtCheck.script;
      usesDarwinHostLocale = hasScriptLine ".*LANG=en_US[.]UTF-8.*" treefmtCheck.script;
      avoidsDeprecatedDarwinAlias = !(hasScriptLine ".*stdenv[.]isDarwin.*" treefmtCheck.script);
    };
    expected = {
      checkName = "treefmt-check";
      hasNoCacheCommand = true;
      usesDarwinHostLocale = true;
      avoidsDeprecatedDarwinAlias = true;
    };
  };

  testNixOSHostSpecsMatchEnvironmentAndExplicitOverrides = {
    expr = {
      defaultArgumentsMatchProcessEnvironment =
        hostSpecsFromEnvironment == hostSpecsWithEnvironmentValues;
      nativeLinuxPresenceMatchesHardwareEnvironment =
        (hostSpecsFromEnvironment ? linux) == (processHardwareConfig != "");
      nativeLinuxSystemFromEnvironment =
        if processHardwareConfig == "" then
          null
        else if processRequestedSystem == "" then
          "x86_64-linux"
        else
          processRequestedSystem;
      nativeLinuxHardwareConfigFromEnvironment =
        if hostSpecsFromEnvironment ? linux then
          hostSpecsFromEnvironment.linux.hardwareConfig
        else
          null;
      wsl = hostSpecsWithoutHardware.nixos;
      nativeLinuxOmittedWithoutHardware = !(hostSpecsWithoutHardware ? linux);
      nativeLinux = hostSpecsWithHardware.linux;
      defaultNativeLinuxSystem = hostSpecsWithHardware.linux.system;
      requestedNativeLinuxSystem = hostSpecsWithRequestedSystem.linux.system;
    };
    expected = {
      defaultArgumentsMatchProcessEnvironment = true;
      nativeLinuxPresenceMatchesHardwareEnvironment = processHardwareConfig != "";
      nativeLinuxSystemFromEnvironment =
        if processHardwareConfig == "" then
          null
        else if processRequestedSystem == "" then
          "x86_64-linux"
        else
          processRequestedSystem;
      nativeLinuxHardwareConfigFromEnvironment =
        if processHardwareConfig == "" then null else processHardwareConfig;
      wsl = {
        system = "x86_64-linux";
        hostPath = ../hosts/wsl;
        homeModulePath = ../home/wsl.nix;
      };
      nativeLinuxOmittedWithoutHardware = true;
      nativeLinux = {
        system = "x86_64-linux";
        hostPath = ../hosts/linux;
        homeModulePath = ../home/linux.nix;
        hardwareConfig = "/etc/nixos/hardware-configuration.nix";
      };
      defaultNativeLinuxSystem = "x86_64-linux";
      requestedNativeLinuxSystem = "aarch64-linux";
    };
  };

  testStandaloneHomeOutputsUseCanonicalOsModules = {
    expr = {
      darwin = homeOutputs."aarch64-darwin".modules;
      x86Linux = homeOutputs."x86_64-linux".modules;
      armLinux = homeOutputs."aarch64-linux".modules;
    };
    expected = {
      darwin = [ ../home/darwin.nix ];
      x86Linux = [ ../home/linux.nix ];
      armLinux = [ ../home/linux.nix ];
    };
  };

  testNixOSHomeManagerGeneratedWiringUsesEnvironmentUser = {
    expr = {
      user = defaultHomeManagerUser.imports;
      selectedUser = builtins.attrNames homeManagerModule."home-manager".users;
      usesGlobalPackages = homeManagerModule."home-manager".useGlobalPkgs;
      usesUserPackages = homeManagerModule."home-manager".useUserPackages;
    };
    expected = {
      user = [ ../home/wsl.nix ];
      selectedUser = [ expectedProcessUser ];
      usesGlobalPackages = true;
      usesUserPackages = true;
    };
  };

  testNixOSHomeManagerGeneratedWiringHonorsExplicitUserOverride = {
    expr = {
      configuredUserModule = customHomeManagerUser.imports;
      configuredUserList = builtins.attrNames customUserHomeManagerModule."home-manager".users;
    };
    expected = {
      configuredUserModule = [ ../home/wsl.nix ];
      configuredUserList = [ "alice" ];
    };
  };

  testSupportedSystemsExcludeIntelDarwin = {
    expr = supportedSystems;
    expected = [
      "aarch64-darwin"
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
