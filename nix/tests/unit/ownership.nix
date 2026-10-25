{ inputs }:
let
  bashTests = ../../../tests/bash;
  bashEntries = builtins.readDir bashTests;
  linesOf = source: builtins.filter builtins.isString (builtins.split "\n" source);
  nixUnitRegistry = builtins.readFile ../default.nix;
  nixFilesUnder =
    directory: prefix:
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
  # Every file under unit/ is a test module; fixtures and build checks live outside it.
  nixUnitModuleFiles = allNixTestFiles;
  buildFiles = nixFilesUnder ../build "";
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
            (builtins.readFile (bashTests + "/${name}"))
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

  testEveryRecursiveNixUnitModuleIsRegisteredExactlyOnce = {
    expr =
      nixUnitModuleFiles != [ ]
      &&
        builtins.sort builtins.lessThan (
          builtins.filter (name: name != null) (
            builtins.map (
              line:
              let
                match = builtins.match "^[[:space:]]*(nix-unit[.]tests[[:space:]]*=[[:space:]]*)?(//[[:space:]]*)?[(]import[[:space:]]+[.]/unit/([^ )]+).*" line;
              in
              if match == null then null else builtins.elemAt match 2
            ) (linesOf nixUnitRegistry)
          )
        ) == nixUnitModuleFiles;
    expected = true;
  };

  testNixTestAttributeNamesAreUnique = {
    expr =
      builtins.length nixTestAttributeNames
      == builtins.length (inputs.nixpkgs.lib.unique nixTestAttributeNames);
    expected = true;
  };

  testDedicatedBuildChecksHaveOwners = {
    expr = {
      buildChecksRegisteredExactlyOnce =
        buildFiles != [ ]
        &&
          builtins.sort builtins.lessThan (
            builtins.filter (name: name != null) (
              builtins.map (
                line:
                let
                  match = builtins.match ".*= import [.]/build/([^ ]+).*" line;
                in
                if match == null then null else builtins.head match
              ) (linesOf nixUnitRegistry)
            )
          ) == buildFiles;
      hardwareFixtureExists = builtins.pathExists ../fixtures/hardware-configuration.nix;
      sharedPackageFixtureExists = builtins.pathExists ../fixtures/packages.nix;
    };
    expected = {
      buildChecksRegisteredExactlyOnce = true;
      hardwareFixtureExists = true;
      sharedPackageFixtureExists = true;
    };
  };
}
