{ inputs }:
let
  pkgs = import inputs.nixpkgs {
    system = "aarch64-darwin";
    config.allowUnfree = true;
  };
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
in
{
  testOxlintPathEntriesExposeWinGetLinksDirectory = {
    expr = sets.wingetPathEntries.oxlint;
    expected = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Links" ];
  };
}
