{ lib, ... }:
let
  reloadCommand = "rg --line-number --no-heading --color=always -- {q} || true";
in
{
  programs.ripgrep.arguments = [
    "--smart-case"
    "--hidden"
    "--glob=!.git/*"
  ];

  programs.zsh.initContent = lib.mkBefore ''
    if command -v rg >/dev/null 2>&1 && command -v fzf >/dev/null 2>&1; then
      rfg() {
        local selected file line
        selected=$(
          fzf --ansi --disabled --query "$*" \
            --bind 'start:reload:${reloadCommand}' \
            --bind 'change:reload:${reloadCommand}' \
            --delimiter : \
            --preview 'bat --color=always --highlight-line {2} -- {1}' \
            --preview-window 'right:60%,+{2}+3/3,~3'
        ) || return

        file=''${selected%%:*}
        line=''${''${selected#*:}%%:*}
        [[ -n $file ]] && ''${EDITOR:-vi} "+$line" "$file"
      }
    fi
  '';
}
