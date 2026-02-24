# treefmt-nix configuration
# Formatter settings are in .treefmt.toml (source of truth)
# This file only installs formatters via Nix
#
# References:
# - treefmt config: https://treefmt.com/v2.1/getting-started/configure/
# - treefmt-nix examples: https://github.com/numtide/treefmt-nix/tree/main/examples
_: {
  perSystem =
    { pkgs, ... }:
    {
      treefmt = {
        projectRootFile = "flake.nix";

        # Install formatters (settings come from .treefmt.toml)
        programs = {
          nixfmt.enable = true; # *.nix
          shfmt.enable = true; # *.sh
          taplo.enable = true; # *.toml
          stylua.enable = true; # *.lua
          dprint.enable = true; # *.md
          oxfmt.enable = true; # *.json, *.yaml, *.yml
        };

        # Custom formatters not in treefmt-nix programs
        settings.formatter = {
          # PowerShell (no built-in support)
          powershell = {
            command = "${pkgs.powershell}/bin/pwsh";
            options = [
              "-NoProfile"
              "-Command"
              "& { $content = Get-Content -Raw -LiteralPath $env:FILENAME; Import-Module PSScriptAnalyzer -Force; $formatted = Invoke-Formatter -ScriptDefinition $content; Set-Content -LiteralPath $env:FILENAME -Value $formatted -Encoding utf8BOM }"
            ];
            includes = [ "*.ps1" ];
          };
        };
      };
    };
}
