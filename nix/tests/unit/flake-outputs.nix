{ inputs }:
let
  lock = builtins.fromJSON (builtins.readFile ../../../flake.lock);
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
    (import ../../hosts {
      inputs = {
        nix-darwin.packages.${system}.darwin-rebuild.executable = "darwin-rebuild";
      };
    }).mkApps
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
    home-manager.lib.homeManagerConfiguration = args: args;
  };
  homeOutputs = (import ../../hosts/configurations.nix { inputs = homeInputs; }).homeConfigurations;

  treefmtModule =
    (import ../../formatter.nix {
      config = { };
      inherit inputs;
    }).perSystem
      {
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
  hostLib = import ../../hosts/default.nix {
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
    hostPath = ../../hosts/x86_64-linux/wsl;
    homeModulePath = ../../hosts/x86_64-linux/wsl/home.nix;
    configuredUser = "nixos";
  };
  nixosArguments = hostLib.mkNixos wslNixosArguments;
  customUserNixosArguments = hostLib.mkNixos (wslNixosArguments // { configuredUser = "alice"; });
  findHomeManagerModule =
    arguments:
    builtins.head (
      builtins.filter (module: builtins.isAttrs module && module ? "home-manager") arguments.modules
    );
  homeManagerModule = findHomeManagerModule nixosArguments;
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

  supportedSystems = builtins.attrNames inputs.self.checks;

in
{
  testFlakeHasNoIntermediateLibOrFlakesDirectories = {
    expr = {
      oldLib = builtins.pathExists ../../lib;
      oldFlakes = builtins.pathExists ../../flakes;
      hostConstruction = builtins.pathExists ../../hosts/default.nix;
      registryPresent = builtins.pathExists ../default.nix;
      packageOutputs = builtins.pathExists ../../packages/outputs.nix;
      formatter = builtins.pathExists ../../formatter.nix;
    };
    expected = {
      oldLib = false;
      oldFlakes = false;
      hostConstruction = true;
      registryPresent = true;
      packageOutputs = true;
      formatter = true;
    };
  };

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
    ];
  };

  testFlakeLockPlatformInputsFollowRootNixpkgs = {
    expr = {
      darwin = lock.nodes.${rootInputs."nix-darwin"}.inputs.nixpkgs;
    };
    expected = {
      darwin = [ "nixpkgs" ];
    };
  };

  testNixosVscodeServerUsesRootFlakeParts = {
    expr = lock.nodes.${rootInputs."nixos-vscode-server"}.inputs."flake-parts";
    expected = [ rootInputs."flake-parts" ];
  };

  testRunnerAppsEvaluateForTheirSupportedPlatforms = {
    expr = {
      darwin = darwinApps.apps.darwin-rebuild.program;
      linux = linuxApps.apps;
      unsupportedPlatformHasNoRunnerApps = unsupportedApps.apps == { };
    };
    expected = {
      darwin = "darwin-rebuild";
      linux = { };
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
      requestedNativeLinuxHost = hostSpecsWithRequestedSystem.linux.hostPath;
      requestedNativeLinuxHome = hostSpecsWithRequestedSystem.linux.homeModulePath;
    };
    expected = {
      wsl = {
        system = "x86_64-linux";
        hostPath = ../../hosts/x86_64-linux/wsl;
        homeModulePath = ../../hosts/x86_64-linux/wsl/home.nix;
      };
      nativeLinuxOmittedWithoutHardware = true;
      nativeLinux = {
        system = "x86_64-linux";
        hostPath = ../../hosts/x86_64-linux/nixos;
        homeModulePath = ../../hosts/x86_64-linux/home.nix;
        hardwareConfig = "/etc/nixos/hardware-configuration.nix";
      };
      defaultNativeLinuxSystem = "x86_64-linux";
      requestedNativeLinuxSystem = "aarch64-linux";
      requestedNativeLinuxHost = ../../hosts/aarch64-linux/nixos;
      requestedNativeLinuxHome = ../../hosts/aarch64-linux/home.nix;
    };
  };

  testStandaloneHomeOutputsUseCanonicalOsModules = {
    expr = {
      darwin = map toString homeOutputs."aarch64-darwin".modules;
      x86Linux = map toString homeOutputs."x86_64-linux".modules;
      armLinux = map toString homeOutputs."aarch64-linux".modules;
    };
    expected = {
      darwin = [
        (toString ../../hosts/aarch64-darwin/home.nix)
        (toString ../../modules/shells/zsh)
        (toString ../../modules/lsp.nix)
        (toString ../../modules/terminals/ghostty/defaults.nix)
        (toString ../../hosts/aarch64-darwin/ghostty.nix)
        (toString ../../modules/terminals/wezterm/defaults.nix)
        (toString ../../hosts/aarch64-darwin/wezterm.nix)
      ];
      x86Linux = [
        (toString ../../hosts/x86_64-linux/home.nix)
        (toString ../../modules/shells/zsh)
        (toString ../../modules/lsp.nix)
        (toString ../../modules/terminals/ghostty/defaults.nix)
        (toString ../../hosts/shared/linux-ghostty.nix)
        (toString ../../modules/terminals/wezterm/defaults.nix)
      ];
      armLinux = [
        (toString ../../hosts/aarch64-linux/home.nix)
        (toString ../../modules/shells/zsh)
        (toString ../../modules/lsp.nix)
        (toString ../../modules/terminals/ghostty/defaults.nix)
        (toString ../../hosts/shared/linux-ghostty.nix)
        (toString ../../modules/terminals/wezterm/defaults.nix)
      ];
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
      user = [ ../../hosts/x86_64-linux/wsl/home.nix ];
      selectedUser = [ "nixos" ];
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
      configuredUserModule = [ ../../hosts/x86_64-linux/wsl/home.nix ];
      configuredUserList = [ "alice" ];
    };
  };

  testSupportedSystemsExcludeIntelDarwin = {
    expr = supportedSystems;
    expected = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
