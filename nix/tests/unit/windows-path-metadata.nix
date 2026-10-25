{ inputs }:
{
  testWindowsPathMetadata = {
    expr =
      (import ../fixtures/packages.nix { inherit inputs; }).windowsPackages."wez.wezterm".pathEntries;
    expected = [ "%ProgramFiles%\\WezTerm" ];
  };
}
