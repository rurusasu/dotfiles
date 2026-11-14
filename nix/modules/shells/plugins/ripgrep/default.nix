{
  config,
  lib,
  pkgs,
  ...
}:
let
  base64 = lib.getExe' pkgs.coreutils "base64";
  reloadCommand = ''
    rg --json --color=never -- {q} | ${lib.getExe pkgs.jq} -r ${lib.escapeShellArg ''
      select(.type == "match") | .data |
      [(.path.bytes // (.path.text | @base64)), .line_number,
       ([.path.text // "(binary path)", .line_number,
         .lines.text // "(binary match)"] | join(":"))] | @tsv
    ''} || true
  '';
  preview = pkgs.writeShellScript "rfg-preview" ''
    set -eu
    [[ $2 =~ ^[1-9][0-9]*$ ]] || exit 1
    file=$(printf '%s' "$1" | ${base64} --decode && printf .) || exit
    file=''${file%.}
    ${
      if config.programs.bat.enable then
        ''
          exec ${lib.getExe config.programs.bat.package} --color=always --highlight-line "$2" -- "$file"
        ''
      else
        ''
          exec ${lib.getExe' pkgs.coreutils "cat"} -- "$file"
        ''
    }
  '';
in
{
  config = lib.mkMerge [
    { programs.ripgrep.enable = true; }
    (lib.mkIf config.programs.ripgrep.enable {
      home.shellAliases.grep = "rg";
      programs = {
        ripgrep = {
          arguments = [
            "--smart-case"
            "--hidden"
            "--glob=!.git/*"
          ];
        };

        zsh.initContent = lib.mkIf config.programs.zsh.enable (
          lib.mkBefore ''
            if command -v rg >/dev/null 2>&1 && command -v fzf >/dev/null 2>&1; then
              rfg() {
                local selected encoded file line display
                selected=$(
                  fzf --disabled --query "$*" \
                    --bind ${lib.escapeShellArg "start:reload:${reloadCommand}"} \
                    --bind ${lib.escapeShellArg "change:reload:${reloadCommand}"} \
                    --delimiter '\t' --with-nth '3..' \
                    --preview ${lib.escapeShellArg "${preview} {1} {2}"} \
                    --preview-window 'right:60%,+{2}+3/3,~3'
                ) || return

                IFS=$'\t' read -r encoded line display <<< "$selected" || return
                [[ $line == <1-> ]] || return 1
                file=$(printf '%s' "$encoded" | ${base64} --decode && printf .) || return
                file=''${file%.}
                [[ -n $file ]] && ''${EDITOR:-vi} "+$line" -- "$file"
              }
            fi
          ''
        );
      };
    })
  ];
}
