{ inputs }:
let
  lock = builtins.fromJSON (builtins.readFile ../../../flake.lock);
  rootInputs = lock.nodes.${lock.root}.inputs;

  mkApps =
    {
      system,
      isDarwin,
    }:
    (import ../../default.nix {
      inputs = {
        nix-darwin.packages.${system}.darwin-rebuild.executable = "darwin-rebuild";
        home-manager.packages.${system}.home-manager.executable = "home-manager";
      };
    }).perSystem
      {
        inherit system;
        pkgs.stdenv.hostPlatform = {
          inherit isDarwin;
        };
        lib = {
          getExe = package: package.executable;
          getExe' = package: binary: "${package.executable}/${binary}";
          optionalAttrs = condition: attrs: if condition then attrs else { };
        };
      };

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

in
{
  testConsolidatedDefaultsPublishGeneratedAndDarwinPackages = {
    expr = builtins.mapAttrs (_: packages: builtins.attrNames packages) inputs.self.packages;
    expected = {
      aarch64-darwin = [
        "darwin-dia-browser"
        "keybindings-json"
      ];
      aarch64-linux = [ "keybindings-json" ];
      x86_64-linux = [ "keybindings-json" ];
    };
  };

  testFlakeHasNoIntermediateLibOrFlakesDirectories = {
    expr = {
      oldLib = builtins.pathExists ../../lib;
      oldFlakes = builtins.pathExists ../../flakes;
      consolidatedDefaults = builtins.pathExists ../../default.nix;
      splitHostDefinitions = builtins.pathExists ../../hosts/default.nix;
      splitRegistrations = builtins.pathExists ../../hosts/configurations.nix;
      splitHomeDefinitions = builtins.pathExists ../../home/common.nix;
      registryPresent = builtins.pathExists ../default.nix;
      splitPackageOutputs = builtins.pathExists ../../outputs.nix;
      formatter = builtins.pathExists ../../formatter.nix;
    };
    expected = {
      oldLib = false;
      oldFlakes = false;
      consolidatedDefaults = true;
      splitHostDefinitions = false;
      splitRegistrations = false;
      splitHomeDefinitions = false;
      registryPresent = true;
      splitPackageOutputs = false;
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
        }).apps.darwin-rebuild.program;
      linux =
        (mkApps {
          system = "x86_64-linux";
          isDarwin = false;
        }).apps;
    };
    expected = {
      darwin = "darwin-rebuild";
      linux.home-manager.program = "home-manager";
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

  testStandaloneHomeOutputsSelectOsSpecificSigners = {
    expr = builtins.mapAttrs (
      _: home: home.config.programs.git.signing.signer
    ) inputs.self.homeConfigurations;
    expected = {
      aarch64-darwin = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
      aarch64-linux = "/opt/1Password/op-ssh-sign";
      x86_64-linux = "/opt/1Password/op-ssh-sign";
    };
  };

  testRegisteredWslIntegratesHomeManagerWithItsDefaultUser = {
    expr =
      let
        cfg = inputs.self.nixosConfigurations.nixos.config;
        home = cfg.home-manager.users.${cfg.wsl.defaultUser};
      in
      {
        system = cfg.nixpkgs.hostPlatform.system;
        user = home.home.username;
        directory = home.home.homeDirectory;
        nix = home.nix.package == cfg.nix.package;
        globalPackages = cfg.home-manager.useGlobalPkgs;
        userPackages = cfg.home-manager.useUserPackages;
      };
    expected = {
      system = "x86_64-linux";
      user = "nixos";
      directory = "/home/nixos";
      nix = true;
      globalPackages = true;
      userPackages = true;
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
