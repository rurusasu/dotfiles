{ homeConfigurations }:
{
  testObsidianIsSelectedByPlatformModules = {
    expr = map (
      home:
      builtins.any (package: package.drvPath == home.pkgs.obsidian.drvPath) home.config.home.packages
    ) homeConfigurations.homes;
    expected = map (_: true) homeConfigurations.homes;
  };
}
