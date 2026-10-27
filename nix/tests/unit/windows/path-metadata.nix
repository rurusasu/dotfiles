{ fixtures }:
{
  testWindowsPathMetadata = {
    expr = fixtures.windowsPackages."wez.wezterm".pathEntries;
    expected = [ "%ProgramFiles%\\WezTerm" ];
  };
}
