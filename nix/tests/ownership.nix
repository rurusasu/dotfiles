let
  bashTests = ../../tests/bash;
  bashEntries = builtins.readDir bashTests;
  batsTests = builtins.sort builtins.lessThan (
    builtins.filter
      (name: bashEntries.${name} == "regular" && builtins.match ".*\\.bats" name != null)
      (builtins.attrNames bashEntries)
  );
  linesOf = source: builtins.filter builtins.isString (builtins.split "\n" source);
  # Match executable command forms, rather than comments or diagnostic strings.
  hasNixEvalCommand = line:
    builtins.match
      "^[[:space:]]*(run[[:space:]]+[^#]*[[:space:]]+)?nix[[:space:]]+eval([[:space:]]|$).*"
      line
      != null
    || builtins.match
      "^[[:space:]]*\"?\\$(\\{[A-Za-z_][A-Za-z0-9_]*\\}|[A-Za-z_][A-Za-z0-9_]*)\"?[[:space:]]+eval([[:space:]]|$).*"
      line
      != null;
  hasNixEvalCommandIn = source:
    builtins.any hasNixEvalCommand (linesOf source);
  nixEvalOwners = builtins.filter (
    name: hasNixEvalCommandIn (builtins.readFile (bashTests + "/${name}"))
  ) batsTests;
  expectedNixEvalOwners = [
    "nixos_wsl_postinstall.bats"
    "package_catalog.bats"
  ];
  packageCatalog = builtins.readFile (bashTests + "/package_catalog.bats");
  packageCatalogTests = builtins.filter
    (line: builtins.match "^[[:space:]]*@test[[:space:]].*" line != null)
    (linesOf packageCatalog);
  packageCatalogTestNames = builtins.map
    (line: builtins.head (builtins.match "^[[:space:]]*@test[[:space:]]+\"([^\"]+)\"[[:space:]]*[{].*" line))
    packageCatalogTests;
  homeReadme = builtins.readFile ./home/README.md;
  classifiedTestNames = builtins.filter (name: name != null) (builtins.map
    (line:
      let
        match = builtins.match "^[|][[:space:]]*[0-9]+[[:space:]]*[|][[:space:]]*`([^`]+)`[[:space:]]*[|][[:space:]]*$" line;
      in
      if match == null then null else builtins.head match)
    (linesOf homeReadme));
  sortedPackageCatalogTestNames = builtins.sort builtins.lessThan packageCatalogTestNames;
  sortedClassifiedTestNames = builtins.sort builtins.lessThan classifiedTestNames;
  macosConfig = builtins.readFile (bashTests + "/macos_config.bats");
in
{
  testNixEvalBatsHaveExplicitTemporaryOwnership = {
    expr = nixEvalOwners;
    expected = expectedNixEvalOwners;
  };

  testPackageCatalogHasClassifiedTestCount = {
    expr = builtins.length packageCatalogTests;
    expected = 46;
  };

  testPackageCatalogNamesMatchTheReadmeClassification = {
    expr = sortedPackageCatalogTestNames == sortedClassifiedTestNames;
    expected = true;
  };

  testHomeManagerStructureIsNotOwnedByBats = {
    expr = builtins.map (name: builtins.pathExists (bashTests + "/${name}")) [
      "home_layout.bats"
      "flake_outputs.bats"
    ];
    expected = [
      false
      false
    ];
  };

  testDarwinConfigBatsContainsOnlyRuntimeContracts = {
    expr = !hasNixEvalCommandIn macosConfig;
    expected = true;
  };
}
