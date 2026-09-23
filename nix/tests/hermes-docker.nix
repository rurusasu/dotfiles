{ inputs }:
let
  systems = [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];
  check =
    system:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      sets = import ../packages/sets.nix {
        inherit pkgs;
        inherit (pkgs) lib;
        codexPackage = pkgs.hello;
      };
      support = sets.supportReport.hermes-docker;
      dockerPackageNamesIn = packages:
        builtins.map (package: package.name) (
          builtins.filter (
            package: builtins.elem package.name [ "hermes-docker" "docker-desktop" ]
          ) packages
        );
      selectedPackages = sets.darwinHomePackagesForInstallFeatures [ "WithHermes" ];
    in
    {
      selectedWithHermes =
        builtins.elem "hermes-docker" (dockerPackageNamesIn selectedPackages);
      selectedDockerPackageNames = dockerPackageNamesIn selectedPackages;
      selectedByDefault =
        dockerPackageNamesIn (sets.darwinHomePackagesForInstallFeatures [ ]) != [ ];
      installFeature = support.installFeature;
      darwinProvider = support.darwin.provider;
      darwinSource = support.darwin.source;
      darwinCommand = support.darwin.identity.command;
      linuxUnsupported = (support.linux.unsupported or "") != "";
      windowsUnsupported = (support.windows.unsupported or "") != "";
    };
in
{
  testHermesDockerIsAnOptInDarwinHomePackage = {
    expr = builtins.map check systems;
    expected = builtins.map
      (selectedWithHermes: {
        inherit selectedWithHermes;
        selectedDockerPackageNames = if selectedWithHermes then [ "hermes-docker" ] else [ ];
        selectedByDefault = false;
        installFeature = "WithHermes";
        darwinProvider = "nix";
        darwinSource = "dotfiles";
        darwinCommand = "hermes-docker";
        linuxUnsupported = true;
        windowsUnsupported = true;
      })
      [ true false false ];
  };

  testHermesDesktopDockerLauncherIsAnOptInDarwinHomePackage =
    let
      system = "aarch64-darwin";
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      sets = import ../packages/sets.nix {
        inherit pkgs;
        inherit (pkgs) lib;
        codexPackage = pkgs.hello;
      };
      launcherPackages = builtins.filter (
        package: package.name == "hermes-desktop-docker"
      ) (sets.darwinHomePackagesForInstallFeatures [ "WithHermes" ]);
      launcher = if launcherPackages == [ ] then null else builtins.head launcherPackages;
    in
    {
      expr = {
        selectedWithHermes = builtins.length launcherPackages == 1;
        selectedByDefault = builtins.any (
          package: package.name == "hermes-desktop-docker"
        ) (sets.darwinHomePackagesForInstallFeatures [ ]);
        packageName = if launcher == null then null else launcher.name;
        launcherCommand =
          if launcher == null then null else builtins.baseNameOf (pkgs.lib.getExe launcher);
        declaredCommand = sets.supportReport.hermes-desktop-docker.darwin.identity.command;
      };
      expected = {
        selectedWithHermes = true;
        selectedByDefault = false;
        packageName = "hermes-desktop-docker";
        launcherCommand = "hermes-desktop-docker";
        declaredCommand = "hermes-desktop-docker";
      };
    };
}
