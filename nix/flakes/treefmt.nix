# treefmt-nix configuration
# Formatter settings are in .treefmt.toml (source of truth)
# This file only installs formatters via Nix
#
# References:
# - treefmt config: https://treefmt.com/v2.1/getting-started/configure/
# - treefmt-nix examples: https://github.com/numtide/treefmt-nix/tree/main/examples
{ config, ... }:
{
  perSystem =
    { pkgs, config, ... }:
    {
      # devShell with treefmt formatters + Nix linters
      devShells.default = pkgs.mkShell {
        packages =
          config.treefmt.build.devShell.nativeBuildInputs
          ++ (with pkgs; [
            statix
            deadnix
          ]);
      };

      treefmt = {
        projectRootFile = "flake.nix";

        # Install formatters (settings come from .treefmt.toml)
        programs = {
          nixfmt.enable = true; # *.nix
          shfmt.enable = true; # *.sh
          taplo.enable = true; # *.toml
          stylua.enable = true; # *.lua
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
              "& { $ErrorActionPreference = 'Stop'; if (-not (Get-Module -ListAvailable PSScriptAnalyzer | Where-Object Version -eq '1.22.0')) { Install-Module -Name PSScriptAnalyzer -RequiredVersion 1.22.0 -Scope CurrentUser -Force -Repository PSGallery | Out-Null }; Import-Module PSScriptAnalyzer -RequiredVersion 1.22.0 -Force; $content = Get-Content -Raw -LiteralPath $env:FILENAME; $formatted = Invoke-Formatter -ScriptDefinition $content; Set-Content -LiteralPath $env:FILENAME -Value $formatted -Encoding utf8 }"
            ];
            includes = [ "*.ps1" ];
          };
        };
      };
    };
}
