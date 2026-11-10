{ homeConfigurations }:
{
  testNodejsIsNotInstalledAsAStandalonePackage = {
    expr = map (package: package.drvPath) (
      builtins.filter (
        package: (package.pname or null) == "nodejs"
      ) homeConfigurations.common.config.home.packages
    );
    expected = [ ];
  };
}
