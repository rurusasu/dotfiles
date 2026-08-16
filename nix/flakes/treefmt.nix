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

        # treefmt-nix still uses the deprecated stdenv.isDarwin alias in its
        # default check. Keep the same check semantics while nixpkgs enforces
        # the hostPlatform API through the warning-free CI gate.
        build.check =
          projectRoot:
          pkgs.runCommandLocal "treefmt-check"
            {
              buildInputs = [
                pkgs.git
                pkgs.git-lfs
                config.treefmt.build.wrapper
              ];
              meta.description = "Check that the project tree is formatted";
            }
            ''
              set -e
              PRJ=$TMP/project
              cp -r ${projectRoot} $PRJ
              chmod -R a+w $PRJ
              cd $PRJ
              export HOME=$TMPDIR
              cat > $HOME/.gitconfig <<EOF
              [user]
                name = Nix
                email = nix@localhost
              [init]
                defaultBranch = main
              EOF
              git init --quiet
              git add .
              git commit -m init --quiet
              export LANG=${if pkgs.stdenv.hostPlatform.isDarwin then "en_US.UTF-8" else "C.UTF-8"}
              export LC_ALL=${if pkgs.stdenv.hostPlatform.isDarwin then "en_US.UTF-8" else "C.UTF-8"}
              treefmt --version
              treefmt --no-cache
              git status --short
              git --no-pager diff --exit-code
              touch $out
            '';

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
              "& { $ErrorActionPreference = 'Stop'; if (-not (Get-Module -ListAvailable PSScriptAnalyzer | Where-Object Version -eq '1.22.0')) { Install-Module -Name PSScriptAnalyzer -RequiredVersion 1.22.0 -Scope CurrentUser -Force -Repository PSGallery | Out-Null }; Import-Module PSScriptAnalyzer -RequiredVersion 1.22.0 -Force; $target = if (-not [string]::IsNullOrWhiteSpace($env:FILENAME)) { $env:FILENAME } elseif ($args.Count -gt 0) { $args[0] } else { throw 'treefmt did not pass a filename' }; $raw = Get-Content -Raw -LiteralPath $target; $crlf = [string][char]13 + [string][char]10; $lf = [string][char]10; $content = $raw.Replace($crlf, $lf).Replace($lf, $crlf); $formatted = Invoke-Formatter -ScriptDefinition $content; $normalized = $formatted.Replace($crlf, $lf).Replace($lf, $crlf); if ($normalized -ne $raw) { [System.IO.File]::WriteAllText($target, $normalized, [System.Text.UTF8Encoding]::new($false)) } }"
            ];
            includes = [ "*.ps1" ];
          };
        };
      };
    };
}
