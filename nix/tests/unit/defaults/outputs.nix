{
  inputs,
  code,
  files,
}:
let
  lock = builtins.fromJSON (builtins.readFile files."flake.lock");
  rootInputs = lock.nodes.${lock.root}.inputs;

  mkApps =
    {
      system,
      isDarwin,
    }:
    (code.nix.defaults {
      nix-darwin.packages.${system}.darwin-rebuild.executable = "darwin-rebuild";
      home-manager.packages.${system}.home-manager.executable = "home-manager";
    }).perSystem
      {
        inherit system;
        config = { };
        pkgs.stdenv.hostPlatform = {
          inherit isDarwin;
        };
        lib = {
          getExe = package: package.executable;
        };
      };

in
{
  testFlakeLockPlatformInputsFollowRootNixpkgs = {
    expr = {
      darwin = lock.nodes.${rootInputs."nix-darwin"}.inputs.nixpkgs;
    };
    expected = {
      darwin = [ "nixpkgs" ];
    };
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

  testRegisteredWslIntegratesHomeManagerWithItsDefaultUser = {
    expr =
      let
        cfg = inputs.self.nixosConfigurations.wsl.config;
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
