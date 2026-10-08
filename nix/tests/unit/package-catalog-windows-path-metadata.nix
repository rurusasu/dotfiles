{ inputs }:
let
  pkgs = (import ../fixtures/packages.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  verifierPackageRoots = {
    "Task.Task" = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\Task.Task*" ];
    "hadolint.hadolint" = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\hadolint.hadolint*" ];
    "tree-sitter.tree-sitter-cli" = [
      "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\tree-sitter.tree-sitter-cli*"
    ];
    "astral-sh.uv" = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\astral-sh.uv*" ];
  };
in
{
  testWindowsPathMetadata = {
    expr = {
      wingetPathEntries = {
        nodejs = sets.wingetPathEntries.nodejs;
        "Task.Task" = sets.wingetPathEntries."Task.Task";
      }
      // verifierPackageRoots
      // {
        "AgileBits.1Password.CLI" = sets.wingetPathEntries."AgileBits.1Password.CLI";
      };
      onePasswordPortableLinkAliasAbsent =
        !(builtins.hasAttr "AgileBits.1Password.CLI" sets.wingetPortableLinksById);
    };
    expected = {
      wingetPathEntries = {
        nodejs = [ "%ProgramFiles%\\nodejs" ];
        "Task.Task" = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\Task.Task*" ];
        "hadolint.hadolint" = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\hadolint.hadolint*" ];
        "tree-sitter.tree-sitter-cli" = [
          "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\tree-sitter.tree-sitter-cli*"
        ];
        "astral-sh.uv" = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\astral-sh.uv*" ];
        "AgileBits.1Password.CLI" = [
          "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\AgileBits.1Password.CLI*"
        ];
      };
      onePasswordPortableLinkAliasAbsent = true;
    };
  };
}
