# treefmt-nix configuration
# Settings and runtime dependencies are declared here. treefmt-nix generates
# configuration in the Nix store and passes it explicitly to each formatter.
#
# References:
# - treefmt config: https://treefmt.com/v2.1/getting-started/configure/
# - treefmt-nix examples: https://github.com/numtide/treefmt-nix/tree/main/examples
{ pkgs, ... }:
{
  projectRootFile = "flake.nix";

  programs = {
    nixfmt.enable = true; # *.nix
    shfmt.enable = true; # *.sh
    taplo = {
      enable = true;
      settings.formatting = {
        align_entries = false;
        array_trailing_comma = true;
        array_auto_expand = true;
        array_auto_collapse = false;
        compact_arrays = false;
        compact_inline_tables = false;
        column_width = 100;
        indent_tables = false;
        indent_entries = false;
        reorder_keys = false;
        allowed_blank_lines = 1;
        trailing_newline = true;
      };
    };
    stylua = {
      enable = true;
      settings = {
        column_width = 120;
        indent_type = "Spaces";
        indent_width = 4;
      };
    };
    oxfmt = {
      enable = true;
      includes = [
        "*.json"
        "*.yaml"
        "*.yml"
      ];
    };
    dprint = {
      enable = true;
      includes = [ "*.md" ];
      settings = {
        lineWidth = 100;
        markdown = {
          lineWidth = 100;
          textWrap = "maintain";
          emphasisKind = "asterisks";
          strongKind = "asterisks";
          newLineKind = "lf";
        };
        plugins = pkgs.dprint-plugins.getPluginList (plugins: [ plugins.dprint-plugin-markdown ]);
      };
    };
  };

  # Custom formatters not in treefmt-nix programs
  settings.formatter = {
    oxfmt = {
      options = [
        "--write"
        "--config"
        (toString (
          (pkgs.formats.json { }).generate "oxfmtrc.json" {
            printWidth = 100;
            tabWidth = 2;
            useTabs = false;
            semi = true;
            singleQuote = false;
            trailingComma = "es5";
            bracketSpacing = true;
            arrowParens = "always";
            proseWrap = "preserve";
            endOfLine = "lf";
          }
        ))
      ];
    };

    # PowerShell (no built-in support)
    powershell = {
      command = toString (
        pkgs.writeShellScript "dotfiles-powershell-formatter" ''
          export DOTFILES_PSSA_MODULE="${pkgs.vscode-extensions.ms-vscode.powershell}/share/vscode/extensions/ms-vscode.PowerShell/modules/PSScriptAnalyzer"
          exec ${pkgs.powershell}/bin/pwsh "$@"
        ''
      );
      options = [
        "-NoProfile"
        "-Command"
        "& { $ErrorActionPreference = 'Stop'; Import-Module $env:DOTFILES_PSSA_MODULE -Force; $target = if (-not [string]::IsNullOrWhiteSpace($env:FILENAME)) { $env:FILENAME } elseif ($args.Count -gt 0) { $args[0] } else { throw 'treefmt did not pass a filename' }; $raw = Get-Content -Raw -LiteralPath $target -Encoding UTF8; $bytes = [System.IO.File]::ReadAllBytes($target); $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191; $sourcePath = [System.IO.Path]::GetFullPath($target).Replace([char]92, [char]47); $needsBom = $hasBom -or ($sourcePath -match '/scripts/powershell/' -and $raw -match '[^\\x00-\\x7F]'); $crlf = [string][char]13 + [string][char]10; $lf = [string][char]10; $content = $raw.Replace($crlf, $lf).Replace($lf, $crlf); $formatted = Invoke-Formatter -ScriptDefinition $content; $normalized = $formatted.Replace($crlf, $lf).Replace($lf, $crlf); if ($normalized -cne $raw -or $needsBom -ne $hasBom) { [System.IO.File]::WriteAllText($target, $normalized, [System.Text.UTF8Encoding]::new($needsBom)) } }"
      ];
      includes = [
        "*.ps1"
        "*.psm1"
        "*.psd1"
      ];
    };
  };
}
