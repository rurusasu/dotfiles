{ homeConfigurations }:
{
  testTartIsSelectedForDarwinHomes = {
    expr =
      map (home: builtins.any (package: (package.pname or "") == "tart") home.config.home.packages)
        [
          homeConfigurations.darwin
          homeConfigurations.linux
          homeConfigurations.linuxArm
        ];
    expected = [
      true
      false
      false
    ];
  };
}
