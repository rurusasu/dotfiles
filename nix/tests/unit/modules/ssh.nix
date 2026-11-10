{ fixtures }:
{
  testDisabledSshLeavesUserConfigurationUnmanaged = {
    expr = (fixtures.mkHome "x86_64-linux" [ ]).config.home.file ? ".ssh/config";
    expected = false;
  };
}
