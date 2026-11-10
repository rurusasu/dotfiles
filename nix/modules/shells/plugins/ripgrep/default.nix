{ config, lib, ... }:
let
  reloadCommand = "rg --line-number --no-heading --color=always -- {q} || true";
  previewCommand =
    if config.programs.bat.enable then
      "bat --color=always --highlight-line {2} -- {1}"
    else
      "cat -- {1}";
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
                local selected file line
                selected=$(
                  fzf --ansi --disabled --query "$*" \
                    --bind 'start:reload:${reloadCommand}' \
                    --bind 'change:reload:${reloadCommand}' \
                    --delimiter : \
                    --preview ${lib.escapeShellArg previewCommand} \
                    --preview-window 'right:60%,+{2}+3/3,~3'
                ) || return

                file=''${selected%%:*}
                line=''${''${selected#*:}%%:*}
                [[ -n $file ]] && ''${EDITOR:-vi} "+$line" "$file"
              }
            fi
          ''
        );
      };
    })
  ];
}
