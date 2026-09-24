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

  inspectLockedInput =
    spec:
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
    }).perSystem
      {
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
    workmux.packages.aarch64-darwin.default = "workmux";
    workmux.packages.aarch64-linux.default = "workmux";
    workmux.packages.x86_64-linux.default = "workmux";
    home-manager.lib.homeManagerConfiguration = args: args;
  };
  homeOutputs = (import ../flakes/home.nix { inputs = homeInputs; }).flake.homeConfigurations;

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
  hasScriptLine =
    pattern: script:
    builtins.any (line: builtins.match pattern line != null) (
      builtins.filter builtins.isString (builtins.split "\n" script)
    );

  # Capture constructor arguments to assert generated wiring without claiming
  # evaluation of the complete NixOS module graph.
  hostLib = import ../flakes/lib/hosts.nix {
    inputs = {
      nixpkgs.lib = {
        nixosSystem = args: args;
        optionals = condition: values: if condition then values else [ ];
      };
      home-manager.nixosModules.home-manager = "home-manager-module";
    };
  };
  wslNixosArguments = {
    system = "x86_64-linux";
    hostPath = ../hosts/wsl;
    siteLib = { };
    homeModulePath = ../home/wsl.nix;
    configuredUser = "nixos";
  };
  nixosArguments = hostLib.mkNixos wslNixosArguments;
  hermesNixosArguments = hostLib.mkNixos (wslNixosArguments // { withHermes = true; });
  customUserNixosArguments = hostLib.mkNixos (wslNixosArguments // { configuredUser = "alice"; });
  findHomeManagerModule =
    arguments:
    builtins.head (
      builtins.filter (module: builtins.isAttrs module && module ? "home-manager") arguments.modules
    );
  homeManagerModule = findHomeManagerModule nixosArguments;
  hermesHomeManagerModule = findHomeManagerModule hermesNixosArguments;
  customUserHomeManagerModule = findHomeManagerModule customUserNixosArguments;
  defaultHomeManagerUser = homeManagerModule."home-manager".users.nixos;
  customHomeManagerUser = customUserHomeManagerModule."home-manager".users.alice;

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

  systemsFixture = builtins.toFile "supported-systems-fixture.nix" ''
    [
      "aarch64-darwin"
      "x86_64-darwin"
      "x86_64-linux"
      "aarch64-linux"
    ]
  '';
  supportedSystems = (import ../flakes/systems.nix { inputs.systems = systemsFixture; }).systems;

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

  testNixosVscodeServerUsesRootFlakeParts = {
    expr = lock.nodes.${rootInputs."nixos-vscode-server"}.inputs."flake-parts";
    expected = [ rootInputs."flake-parts" ];
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

  testNixOSHostSpecsHonorExplicitHardwareAndSystemOverrides = {
    expr = {
      wsl = hostSpecsWithoutHardware.nixos;
      nativeLinuxOmittedWithoutHardware = !(hostSpecsWithoutHardware ? linux);
      nativeLinux = hostSpecsWithHardware.linux;
      defaultNativeLinuxSystem = hostSpecsWithHardware.linux.system;
      requestedNativeLinuxSystem = hostSpecsWithRequestedSystem.linux.system;
    };
    expected = {
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

  testNixOSHomeManagerGeneratedWiringUsesNixosDefaultUser = {
    expr = {
      user = defaultHomeManagerUser.imports;
      selectedUser = builtins.attrNames homeManagerModule."home-manager".users;
      usesGlobalPackages = homeManagerModule."home-manager".useGlobalPkgs;
      usesUserPackages = homeManagerModule."home-manager".useUserPackages;
    };
    expected = {
      user = [ ../home/wsl.nix ];
      selectedUser = [ "nixos" ];
      usesGlobalPackages = true;
      usesUserPackages = true;
    };
  };

  testNixOSHermesFeaturePropagatesToHostAndHomeManager = {
    expr = {
      hostArgument = hermesNixosArguments.specialArgs.dotfilesWithHermes;
      homeManagerFeature = hermesHomeManagerModule."home-manager".extraSpecialArgs.installFeatures;
    };
    expected = {
      hostArgument = true;
      homeManagerFeature = [ "WithHermes" ];
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
