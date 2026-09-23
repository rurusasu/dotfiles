{ inputs }:
let
  bashTests = ../../tests/bash;
  bashEntries = builtins.readDir bashTests;
  batsTests = builtins.sort builtins.lessThan (
    builtins.filter (
      name: bashEntries.${name} == "regular" && builtins.match ".*\\.bats" name != null
    ) (builtins.attrNames bashEntries)
  );
  linesOf = source: builtins.filter builtins.isString (builtins.split "\n" source);
  # Match executable command forms, rather than comments or diagnostic strings.
  hasNixEvalCommand =
    line:
    builtins.match "^[[:space:]]*(run[[:space:]]+[^#]*[[:space:]]+)?nix[[:space:]]+eval([[:space:]]|$).*" line
    != null
    ||
      builtins.match "^[[:space:]]*\"?\\$([{][A-Za-z_][A-Za-z0-9_]*[}]|[A-Za-z_][A-Za-z0-9_]*)\"?[[:space:]]+eval([[:space:]]|$).*" line
      != null;
  hasNixEvalCommandIn = source: builtins.any hasNixEvalCommand (linesOf source);
  nixEvalOwners = builtins.filter (
    name: hasNixEvalCommandIn (builtins.readFile (bashTests + "/${name}"))
  ) batsTests;
  expectedNixEvalOwners = [
    "nixos_wsl_postinstall.bats"
  ];
  packageCatalog = builtins.readFile (bashTests + "/package_catalog.bats");
  packageCatalogPester = builtins.readFile ../../scripts/powershell/tests/PackageCatalog.Tests.ps1;
  packageCatalogPesterTests = builtins.filter (
    line: builtins.match "^[[:space:]]*It[[:space:]]+'.*'[[:space:]]*[{].*" line != null
  ) (linesOf packageCatalogPester);
  nixUnitRegistry = builtins.readFile ../flakes/tests.nix;
  registryImports = builtins.filter (name: name != null) (
    builtins.map (
      line:
      let
        match = builtins.match "^[[:space:]]*//[[:space:]]*[(]import[[:space:]]+[.][.]/tests/([^ )]+).*" line;
      in
      if match == null then null else builtins.head match
    ) (linesOf nixUnitRegistry)
  );
  nixFilesUnder = directory: prefix:
    let
      entries = builtins.readDir directory;
    in
    builtins.concatLists (
      builtins.map (
        name:
        let
          entryType = entries.${name};
          relativeName = if prefix == "" then name else "${prefix}/${name}";
        in
        if entryType == "regular" && builtins.match ".*[.]nix$" name != null then
          [ relativeName ]
        else if entryType == "directory" then
          nixFilesUnder (directory + "/${name}") relativeName
        else
          [ ]
      ) (builtins.attrNames entries)
    );
  allNixTestFiles = nixFilesUnder ./. "";
  dedicatedBuildAndFixtureModules = [
    "bootstrap-nixos.nix"
    "neovim.nix"
    "hardware-configuration.nix"
  ];
  nixUnitModuleFiles = builtins.filter (
    name: !(builtins.elem name dedicatedBuildAndFixtureModules)
  ) allNixTestFiles;
  nixTestAttributeNames = builtins.concatLists (
    builtins.map (
      name:
      builtins.filter (testName: testName != null) (
        builtins.map (
          line:
          let
            match = builtins.match "^[[:space:]]*(test[A-Za-z0-9_]+)[[:space:]]*=.*" line;
          in
          if match == null then null else builtins.head match
        ) (linesOf (builtins.readFile (./. + "/${name}")))
      )
    ) allNixTestFiles
  );
  packageCatalogModules = builtins.filter (
    name: builtins.match "^package-catalog-.*[.]nix$" name != null
  ) allNixTestFiles;
  systemManagerModules = [
    "system-manager-docker-config.nix"
    "system-manager-host-contracts.nix"
    "system-manager-integrations.nix"
    "system-manager-user-identity.nix"
  ];
  moduleRegisteredExactlyOnce = name:
    builtins.pathExists (./. + "/${name}")
    && builtins.length (builtins.filter (registered: registered == name) registryImports) == 1;
  packageCatalogTests = builtins.filter (
    line: builtins.match "^[[:space:]]*@test[[:space:]].*" line != null
  ) (linesOf packageCatalog);
  batsTestCount = name:
    builtins.length (
      builtins.filter (
        line: builtins.match "^[[:space:]]*@test[[:space:]].*" line != null
      ) (linesOf (builtins.readFile (bashTests + "/${name}")))
    );
  packageCatalogTestNames = builtins.map (
    line:
    builtins.head (builtins.match "^[[:space:]]*@test[[:space:]]+\"([^\"]+)\"[[:space:]]*[{].*" line)
  ) packageCatalogTests;
  tartVmInstaller = builtins.readFile (bashTests + "/tart_vm_installer.bats");
  tartVmInstallerTests = builtins.filter (
    line: builtins.match "^[[:space:]]*@test[[:space:]].*" line != null
  ) (linesOf tartVmInstaller);
  packageChecks = builtins.readFile ../flakes/packages.nix;
  packageSupportOutputs = inputs.self.packages.x86_64-linux;
  packageSupportChecks = inputs.self.checks.x86_64-linux;
  bootstrapNixos = builtins.readFile ./bootstrap-nixos.nix;
  sourceHasLine = source: pattern:
    builtins.any (line: builtins.match pattern line != null) (linesOf source);
  homeReadme = builtins.readFile ./home/README.md;
  classifiedTests = builtins.filter (test: test != null) (
    builtins.map (
      line:
      let
        match = builtins.match
          "^[[:space:]]*[|][[:space:]]*([0-9]+)[[:space:]]*[|][[:space:]]*`([^`]+)`[[:space:]]*[|][[:space:]]*$"
          line;
      in
      if match == null then null else {
        index = builtins.fromJSON (builtins.elemAt match 0);
        name = builtins.elemAt match 1;
      }
    ) (linesOf homeReadme)
  );
  orderedClassifiedTests = builtins.sort (a: b: a.index < b.index) classifiedTests;
  indexedPackageCatalogTests = builtins.genList (
    index: {
      index = index + 1;
      name = builtins.elemAt packageCatalogTestNames index;
    }
  ) (builtins.length packageCatalogTestNames);
  macosConfig = builtins.readFile (bashTests + "/macos_config.bats");
in
{
  testNixEvalBatsHaveExplicitRuntimeOwnership = {
    expr = nixEvalOwners;
    expected = expectedNixEvalOwners;
  };

  testPackageCatalogHasClassifiedTestCount = {
    expr = builtins.length packageCatalogTests;
    expected = 9;
  };

  testPackageCatalogPesterHasExpectedItCount = {
    expr = builtins.length packageCatalogPesterTests;
    expected = 37;
  };

  testTartVmInstallerKeepsOnlyRuntimeAndTaskfileContracts = {
    expr = {
      count = builtins.length tartVmInstallerTests;
      catalogMetadataAssertionRemoved = !sourceHasLine tartVmInstaller
        ".*catalog declares Tart as a Nix command with legacy formula migration metadata.*";
    };
    expected = {
      count = 8;
      catalogMetadataAssertionRemoved = true;
    };
  };

  testMigratedBatsSuitesMatchCurrentLedgerCounts = {
    expr = {
      linuxConfig = batsTestCount "linux_config.bats";
      taskfileRouting = batsTestCount "taskfile_test_routing.bats";
      tartDotfilesSync = batsTestCount "tart_dotfiles_sync.bats";
      packageCatalog = builtins.length packageCatalogTests;
      tartVmInstaller = batsTestCount "tart_vm_installer.bats";
    };
    expected = {
      linuxConfig = 2;
      taskfileRouting = 10;
      tartDotfilesSync = 11;
      packageCatalog = 9;
      tartVmInstaller = 8;
    };
  };

  testSupportReportPackageAndCheckExposeTheSameNamedOutput = {
    expr =
      packageSupportOutputs."package-support-report".drvPath
      == packageSupportChecks."package-provider-coverage".drvPath;
    expected = true;
  };

  testPackageCatalogNamesMatchTheReadmeClassification = {
    expr = orderedClassifiedTests == indexedPackageCatalogTests;
    expected = true;
  };

  testEveryPackageCatalogModuleIsRegisteredExactlyOnce = {
    expr = packageCatalogModules != [ ] && builtins.all moduleRegisteredExactlyOnce packageCatalogModules;
    expected = true;
  };

  testEveryRecursiveNixUnitModuleIsRegisteredExactlyOnce = {
    expr = nixUnitModuleFiles != [ ] && builtins.all moduleRegisteredExactlyOnce nixUnitModuleFiles;
    expected = true;
  };

  testNixTestAttributeNamesAreUnique = {
    expr = builtins.length nixTestAttributeNames == builtins.length (inputs.nixpkgs.lib.unique nixTestAttributeNames);
    expected = true;
  };

  testDedicatedBuildChecksAndVmFixtureHaveOwners = {
    expr = {
      neovimNativeBuild = sourceHasLine packageChecks ".*neovim-native = import \\.\\./tests/neovim[.]nix.*";
      bootstrapNixosVmBuild = sourceHasLine packageChecks ".*bootstrap-nixos-vm = import \\.\\./tests/bootstrap-nixos[.]nix.*";
      hardwareFixtureConsumedByVm = sourceHasLine bootstrapNixos ".*\\./hardware-configuration[.]nix.*";
      allDedicatedFilesExist = builtins.all (name: builtins.pathExists (./. + "/${name}")) dedicatedBuildAndFixtureModules;
    };
    expected = {
      neovimNativeBuild = true;
      bootstrapNixosVmBuild = true;
      hardwareFixtureConsumedByVm = true;
      allDedicatedFilesExist = true;
    };
  };

  testSystemManagerMigrationModulesAreRegisteredExactlyOnce = {
    expr = builtins.all moduleRegisteredExactlyOnce systemManagerModules;
    expected = true;
  };

  testDarwinConfigBatsContainsOnlyRuntimeContracts = {
    expr = !hasNixEvalCommandIn macosConfig;
    expected = true;
  };
}
