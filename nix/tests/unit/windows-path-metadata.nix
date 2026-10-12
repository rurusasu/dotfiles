{ inputs }:
let
  windows = (import ../fixtures/packages.nix { inherit inputs; }).windowsPackages;
in
{
  testWindowsPathMetadata = {
    expr = windows."wez.wezterm".pathEntries;
    expected = [ "%ProgramFiles%\\WezTerm" ];
  };
}
