{ pkgs, ... }:
{
  programs.zsh = {
    enable = true;
    shellAliases = {
      nrs = "sudo nixos-rebuild switch --flake ~/.dotfiles --impure";
      nrt = "sudo nixos-rebuild test --flake ~/.dotfiles --impure";
      nrb = "sudo nixos-rebuild boot --flake ~/.dotfiles --impure";
      find = "fd";
      grep = "rg";
    };
    initContent = ''
      # Alt+Z: zoxide interactive (履歴ベースのディレクトリジャンプ)
      __zoxide_zi_widget() {
        local result
        result="$(${pkgs.zoxide}/bin/zoxide query -i)" && cd "$result"
        zle reset-prompt
      }
      zle -N __zoxide_zi_widget
      bindkey '^[z' __zoxide_zi_widget  # Alt+Z

      # Alt+D: fzf directory search and cd
      __fzf_cd_widget() {
        local dir
        dir="$(${pkgs.fd}/bin/fd -t d | ${pkgs.fzf}/bin/fzf)" && cd "$dir"
        zle reset-prompt
      }
      zle -N __fzf_cd_widget
      bindkey '^[d' __fzf_cd_widget  # Alt+D

      # Alt+T: fzf file/directory search and insert
      __fzf_file_widget() {
        local selected
        selected="$(${pkgs.fd}/bin/fd | ${pkgs.fzf}/bin/fzf)"
        if [[ -n "$selected" ]]; then
          LBUFFER="$LBUFFER$selected"
        fi
        zle reset-prompt
      }
      zle -N __fzf_file_widget
      bindkey '^[t' __fzf_file_widget  # Alt+T

      # Alt+R: fzf command history search
      __fzf_history_widget() {
        local selected
        selected="$(fc -ln 1 | ${pkgs.fzf}/bin/fzf --tac)"
        if [[ -n "$selected" ]]; then
          BUFFER="$selected"
          CURSOR=$#BUFFER
        fi
        zle reset-prompt
      }
      zle -N __fzf_history_widget
      bindkey '^[r' __fzf_history_widget  # Alt+R
    '';
  };
}
