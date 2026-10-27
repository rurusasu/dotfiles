{ homeConfigurations }:
{
  testNautilusIsUnavailableOnDarwin = {
    expr = builtins.any (
      package: (package.pname or "") == "nautilus"
    ) homeConfigurations.darwin.config.home.packages;
    expected = false;
  };
}
