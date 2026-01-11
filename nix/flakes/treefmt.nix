_: {
  perSystem =
    { pkgs, ... }:
    {
      treefmt = {
        package = pkgs.treefmt;
        enableDefaultExcludes = true;
        flakeFormatter = true;
        projectRootFile = "flake.nix";

        programs = {
          # Nix
          nixfmt.enable = true;

          # Shell
          shfmt.enable = true;

          # TOML
          taplo.enable = true;

          # Lua
          stylua.enable = true;

          # Markdown - dprint with explicit includes
          dprint = {
            enable = true;
            includes = [ "*.md" ];
          };
        };

        settings.formatter = {
          # PowerShell - treefmt-nix doesn't have built-in support
          powershell = {
            command = "${pkgs.powershell}/bin/pwsh";
            options = [
              "-NoProfile"
              "-Command"
              "& { $content = Get-Content -Raw -LiteralPath $env:FILENAME; Import-Module PSScriptAnalyzer -Force; $formatted = Invoke-Formatter -ScriptDefinition $content; Set-Content -LiteralPath $env:FILENAME -Value $formatted -Encoding utf8 }"
            ];
            includes = [ "*.ps1" ];
          };

          # JSON/YAML with prettier (oxfmt is not yet in nixpkgs)
          prettier = {
            command = "${pkgs.nodePackages.prettier}/bin/prettier";
            options = [
              "--write"
            ];
            includes = [
              "*.json"
              "*.yaml"
              "*.yml"
            ];
          };
        };
      };
    };
}
