{ inputs }:
let
  lock = builtins.fromJSON (builtins.readFile ../../../flake.lock);
  rootInputs = lock.nodes.${lock.root}.inputs;

  mkApps =
    {
      system,
      isDarwin,
      isLinux,
    }:
    (import ../../hosts {
      inputs = {
        nix-darwin.packages.${system}.darwin-rebuild.executable = "darwin-rebuild";
        home-manager.packages.${system}.home-manager.executable = "home-manager";
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

  homeOutputs =
    (import ../../hosts/configurations.nix {
      inputs = {
        nixpkgs = {
          outPath = builtins.toFile "flake-outputs-nixpkgs-fixture.nix" ''
            { system, ... }:
            {
              stdenv.hostPlatform.system = system;
            }
          '';
          lib.optionals = condition: values: if condition then values else [ ];
        };
        home-manager.lib.homeManagerConfiguration = args: args;
      };
    }).homeConfigurations;

  treefmtCheck =
    (
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
        }
    ).treefmt.build.check
      "/source";
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
    hostPath = ../../hosts/wsl.nix;
    homeModule = ../../home/wsl.nix;
    configuredUser = "nixos";
  };
  findHomeManagerModule =
    arguments:
    builtins.head (
      builtins.filter (module: builtins.isAttrs module && module ? "home-manager") arguments.modules
    );
  homeManagerModule = findHomeManagerModule (hostLib.mkNixos wslNixosArguments);
  customUserHomeManagerModule = findHomeManagerModule (
    hostLib.mkNixos (wslNixosArguments // { configuredUser = "alice"; })
  );

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
  linuxHomeDescription =
    module:
    let
      declarations = module {
        config = { };
        lib = { };
      };
    in
    {
      imports = map (
        imported: if builtins.isPath imported then toString imported else builtins.typeOf imported
      ) declarations.imports;
      inherit (declarations.programs.git.signing) signer;
    };
  expectedLinuxHome = {
    imports = [
      "lambda"
      "lambda"
      (toString ../../modules/discord)
      (toString ../../home/common.nix)
    ];
    signer = "/opt/1Password/op-ssh-sign";
  };

in
{
  testFlakeHasNoIntermediateLibOrFlakesDirectories = {
    expr = {
      oldLib = builtins.pathExists ../../lib;
      oldFlakes = builtins.pathExists ../../flakes;
      hostConstruction = builtins.pathExists ../../hosts/default.nix;
      registryPresent = builtins.pathExists ../default.nix;
      packageOutputs = builtins.pathExists ../../outputs.nix;
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
    expr =
      builtins.map
        (
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
          }
        )
        [
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
      darwin =
        (mkApps {
          system = "aarch64-darwin";
          isDarwin = true;
          isLinux = false;
        }).apps.darwin-rebuild.program;
      linux =
        (mkApps {
          system = "x86_64-linux";
          isDarwin = false;
          isLinux = true;
        }).apps;
      unsupportedPlatformHasNoRunnerApps =
        (mkApps {
          system = "x86_64-freebsd";
          isDarwin = false;
          isLinux = false;
        }).apps == { };
    };
    expected = {
      darwin = "darwin-rebuild";
      linux.home-manager.program = "home-manager";
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
      nativeLinux = hostSpecsWithHardware.linux // {
        homeModule = linuxHomeDescription hostSpecsWithHardware.linux.homeModule;
      };
      defaultNativeLinuxSystem = hostSpecsWithHardware.linux.system;
      requestedNativeLinuxSystem = hostSpecsWithRequestedSystem.linux.system;
      requestedNativeLinuxHost = hostSpecsWithRequestedSystem.linux.hostPath;
      requestedNativeLinuxHome = linuxHomeDescription hostSpecsWithRequestedSystem.linux.homeModule;
    };
    expected = {
      wsl = {
        system = "x86_64-linux";
        hostPath = ../../hosts/wsl.nix;
        homeModule = ../../home/wsl.nix;
      };
      nativeLinuxOmittedWithoutHardware = true;
      nativeLinux = {
        system = "x86_64-linux";
        hostPath = ../../hosts/linux.nix;
        homeModule = expectedLinuxHome;
        hardwareConfig = "/etc/nixos/hardware-configuration.nix";
      };
      defaultNativeLinuxSystem = "x86_64-linux";
      requestedNativeLinuxSystem = "aarch64-linux";
      requestedNativeLinuxHost = ../../hosts/linux.nix;
      requestedNativeLinuxHome = expectedLinuxHome;
    };
  };

  testStandaloneHomeOutputsUseCanonicalOsModules = {
    expr = {
      darwin = map toString (builtins.filter builtins.isPath homeOutputs."aarch64-darwin".modules);
      x86Linux = linuxHomeDescription (builtins.head homeOutputs."x86_64-linux".modules);
      armLinux = linuxHomeDescription (builtins.head homeOutputs."aarch64-linux".modules);
    };
    expected = {
      darwin = [
        (toString ../../home/darwin.nix)
      ];
      x86Linux = expectedLinuxHome;
      armLinux = expectedLinuxHome;
    };
  };

  testNixOSHomeManagerGeneratedWiringUsesNixosDefaultUser = {
    expr = {
      user = homeManagerModule."home-manager".users.nixos.imports;
      selectedUser = builtins.attrNames homeManagerModule."home-manager".users;
      usesGlobalPackages = homeManagerModule."home-manager".useGlobalPkgs;
      usesUserPackages = homeManagerModule."home-manager".useUserPackages;
    };
    expected = {
      user = [ ../../home/wsl.nix ];
      selectedUser = [ "nixos" ];
      usesGlobalPackages = true;
      usesUserPackages = true;
    };
  };

  testNixOSHomeManagerGeneratedWiringHonorsExplicitUserOverride = {
    expr = {
      configuredUserModule = customUserHomeManagerModule."home-manager".users.alice.imports;
      configuredUserList = builtins.attrNames customUserHomeManagerModule."home-manager".users;
    };
    expected = {
      configuredUserModule = [ ../../home/wsl.nix ];
      configuredUserList = [ "alice" ];
    };
  };

  testSupportedSystemsExcludeIntelDarwin = {
    expr = builtins.attrNames inputs.self.checks;
    expected = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
