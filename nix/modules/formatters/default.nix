# Repository formatters and the tools used by local checks and CI.
{ inputs, ... }:
{
  perSystem =
    { config, pkgs, ... }:
    let
      ciTreefmt = inputs.treefmt-nix.lib.evalModule pkgs {
        imports = [ ./treefmt.nix ];
        programs.powershell.enable = true;
      };
      powershellLint = pkgs.writeShellScriptBin "powershell-lint" ''
        exec ${ciTreefmt.config.settings.formatter.powershell.command} \
          -NoProfile -NonInteractive -File ${../../../scripts/powershell/Invoke-StaticAnalysis.ps1} \
          -SourceRoot "$PWD/scripts/powershell"
      '';
    in
    {
      treefmt = {
        imports = [ ./treefmt.nix ];
      };
      devShells.default = pkgs.mkShell {
        inputsFrom = [ config.treefmt.build.devShell ];
        packages = [
          pkgs.pre-commit
          pkgs.go-task
          pkgs.statix
          pkgs.deadnix
        ];
      };
      devShells.ci = pkgs.mkShellNoCC {
        inputsFrom = [ ciTreefmt.config.build.devShell ];
        packages = [
          powershellLint
        ]
        ++ (with pkgs; [
          actionlint
          bash
          coreutils
          gitMinimal
          gnugrep
          gnused
          gnutar
          go-task
          jq
          python3
          statix
          zstd
        ]);
      };
    };
}
