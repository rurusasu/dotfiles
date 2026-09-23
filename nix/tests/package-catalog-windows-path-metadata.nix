{ inputs }:
let
  pkgs = (import ../test-fixtures.nix { inherit inputs; }).mkPkgs "aarch64-darwin";
  sets = import ../packages/sets.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    codexPackage = pkgs.hello;
  };
  verifierPackageRoots = {
    "Task.Task" = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\Task.Task*" ];
    "hadolint.hadolint" = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\hadolint.hadolint*" ];
    "Artempyanykh.Marksman" = [
      "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\Artempyanykh.Marksman*"
    ];
    "astral-sh.ruff" = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\astral-sh.ruff*" ];
    "JohnnyMorganz.StyLua" = [
      "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\JohnnyMorganz.StyLua*"
    ];
    "tamasfe.taplo" = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\tamasfe.taplo*" ];
    "tree-sitter.tree-sitter-cli" = [
      "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\tree-sitter.tree-sitter-cli*"
    ];
    "astral-sh.ty" = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\astral-sh.ty*" ];
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
        _1password-cli = sets.wingetPathEntries._1password-cli;
        "AgileBits.1Password.CLI" = sets.wingetPathEntries."AgileBits.1Password.CLI";
      };
      wingetPortableLinks = {
        "OpenAI.Codex" = sets.wingetPortableLinksById."OpenAI.Codex";
      };
      onePasswordPortableLinkAliasAbsent =
        !(builtins.hasAttr "_1password-cli" sets.wingetPortableLinksById);
    };
    expected = {
      wingetPathEntries = {
        nodejs = [ "%ProgramFiles%\\nodejs" ];
        "Task.Task" = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\Task.Task*" ];
        "hadolint.hadolint" = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\hadolint.hadolint*" ];
        "Artempyanykh.Marksman" = [
          "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\Artempyanykh.Marksman*"
        ];
        "astral-sh.ruff" = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\astral-sh.ruff*" ];
        "JohnnyMorganz.StyLua" = [
          "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\JohnnyMorganz.StyLua*"
        ];
        "tamasfe.taplo" = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\tamasfe.taplo*" ];
        "tree-sitter.tree-sitter-cli" = [
          "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\tree-sitter.tree-sitter-cli*"
        ];
        "astral-sh.ty" = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\astral-sh.ty*" ];
        "astral-sh.uv" = [ "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\astral-sh.uv*" ];
        _1password-cli = [
          "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\AgileBits.1Password.CLI*"
        ];
        "AgileBits.1Password.CLI" = [
          "%LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\AgileBits.1Password.CLI*"
        ];
      };
      wingetPortableLinks."OpenAI.Codex" = {
        linkName = "codex.exe";
        targetPattern = "codex-x86_64-pc-windows-msvc.exe";
      };
      onePasswordPortableLinkAliasAbsent = true;
    };
  };
}
