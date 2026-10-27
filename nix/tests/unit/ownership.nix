{
  inputs,
  fixtures,
  homeConfigurations,
  code,
  files,
  upstream,
}:
let
  bashTests = files.tests.bash.__path;
  bashEntries = builtins.readDir bashTests;
  linesOf = source: builtins.filter builtins.isString (builtins.split "\n" source);
  discover = code.nix.tests.discover;
  unit = discover {
    directory = files.nix.tests.unit.__path;
    args = {
      inherit
        inputs
        fixtures
        homeConfigurations
        code
        files
        upstream
        ;
    };
  };
  build = discover {
    directory = files.nix.tests.build.__path;
    suffix = ".check.nix";
    allowEmptyFiles = true;
    args = {
      inherit
        inputs
        fixtures
        homeConfigurations
        code
        files
        upstream
        ;
      config = { };
      pkgs = fixtures.mkPkgs "x86_64-linux";
    };
  };
  discoveryFixtures = files.nix.tests.fixtures.test-discovery;
  fails = args: !(builtins.tryEval (builtins.attrNames (discover args).values)).success;
  relativeFiles =
    directory: files:
    map (file: inputs.nixpkgs.lib.removePrefix "${toString directory}/" (toString file)) files;
  nixFilesUnder =
    directory:
    let
      entries = builtins.readDir directory;
    in
    builtins.concatMap (
      name:
      let
        path = directory + "/${name}";
      in
      if entries.${name} == "directory" then
        nixFilesUnder path
      else if entries.${name} == "regular" && builtins.match ".*[.]nix$" name != null then
        [ path ]
      else
        [ ]
    ) (builtins.attrNames entries);

in
{
  testNixEvalBatsHaveExplicitRuntimeOwnership = {
    # Match executable command forms, rather than comments or diagnostic strings.
    expr =
      builtins.filter
        (
          name:
          (
            source:
            builtins.any (
              line:
              builtins.match "^[[:space:]]*(run[[:space:]]+[^#]*[[:space:]]+)?nix[[:space:]]+eval([[:space:]]|$).*" line
              != null
              ||
                builtins.match "^[[:space:]]*\"?\\$([{][A-Za-z_][A-Za-z0-9_]*[}]|[A-Za-z_][A-Za-z0-9_]*)\"?[[:space:]]+eval([[:space:]]|$).*" line
                != null
            ) (linesOf source)
          )
            (builtins.readFile files.tests.bash.${name})
        )
        (
          builtins.sort builtins.lessThan (
            builtins.filter (
              name: bashEntries.${name} == "regular" && builtins.match ".*\\.bats" name != null
            ) (builtins.attrNames bashEntries)
          )
        );
    expected = [ ];
  };

  testEveryRecursiveNixUnitModuleIsDiscoveredExactlyOnce = {
    expr =
      unit.files != [ ]
      && unit.files == nixFilesUnder files.nix.tests.unit.__path
      && builtins.length unit.files == builtins.length (inputs.nixpkgs.lib.unique unit.files);
    expected = true;
  };
  testNixTestAttributeNamesAreUnique = {
    expr = builtins.length (builtins.attrNames unit.values) > 0;
    expected = true;
  };
  testDedicatedBuildChecksHaveOwners = {
    expr = {
      buildChecksDiscoveredExactlyOnce =
        build.files != [ ]
        &&
          build.files == builtins.filter (path: inputs.nixpkgs.lib.hasSuffix ".check.nix" (toString path)) (
            nixFilesUnder files.nix.tests.build.__path
          )
        && builtins.length (builtins.attrNames build.values) > 0;
      hardwareFixtureExists = (files.nix.tests.fixtures ? hardware-configuration);
      sharedPackageFixtureExists = (files.nix.tests.fixtures ? packages);
    };
    expected = {
      buildChecksDiscoveredExactlyOnce = true;
      hardwareFixtureExists = true;
      sharedPackageFixtureExists = true;
    };
  };
  testAutomaticUnitDiscoveryFindsNestedSuitesAndSuppliesArguments = {
    expr =
      let
        found = discover {
          directory = discoveryFixtures.valid.__path;
          args.marker = "supplied";
        };
      in
      {
        files = relativeFiles (discoveryFixtures.valid.__path) found.files;
        names = builtins.attrNames found.values;
        argument = found.values.testWithArgument.expr;
      };
    expected = {
      files = [
        "alpha.nix"
        "nested/beta.nix"
      ];
      names = [
        "testNestedSuite"
        "testWithArgument"
      ];
      argument = "supplied";
    };
  };
  testAutomaticTestDiscoveryRejectsDuplicateNames = {
    expr = fails { directory = discoveryFixtures.duplicate.__path; };
    expected = true;
  };
  testAutomaticTestDiscoveryRejectsEmptySuites = {
    expr = fails { directory = discoveryFixtures.empty-suite.__path; };
    expected = true;
  };
  testAutomaticTestDiscoveryRejectsZeroDiscoveredTests = {
    expr = fails { directory = discoveryFixtures.no-suites.__path; };
    expected = true;
  };
  testAutomaticBuildDiscoveryIgnoresHelpersAndPreservesConditionalChecks = {
    expr =
      let
        load =
          enabled:
          (discover {
            directory = discoveryFixtures.build.__path;
            suffix = ".check.nix";
            allowEmptyFiles = true;
            args = { inherit enabled; };
          }).values;
      in
      {
        enabled = builtins.attrNames (load true);
        disabled = builtins.attrNames (load false);
      };
    expected = {
      enabled = [
        "another-check"
        "sample-check"
      ];
      disabled = [ "another-check" ];
    };
  };
  testAutomaticBuildDiscoveryRejectsAnEmptyAggregate = {
    expr = fails {
      directory = discoveryFixtures.empty-suite.__path;
      allowEmptyFiles = true;
    };
    expected = true;
  };
}
