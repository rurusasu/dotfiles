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
      # Ctrl+Alt+Z: zoxide interactive (履歴ベースのディレクトリジャンプ)
      __zoxide_zi_widget() {
        local result
        result="$(${pkgs.zoxide}/bin/zoxide query -i)" && cd "$result"
        zle reset-prompt
      }
      zle -N __zoxide_zi_widget
      bindkey '^[^z' __zoxide_zi_widget  # Ctrl+Alt+Z

      # Ctrl+Alt+D: fzf directory search and cd
      __fzf_cd_widget() {
        local dir
        dir="$(${pkgs.fd}/bin/fd -t d | ${pkgs.fzf}/bin/fzf --height 40% --reverse)" && cd "$dir"
        zle reset-prompt
      }
      zle -N __fzf_cd_widget
      bindkey '^[^d' __fzf_cd_widget  # Ctrl+Alt+D
    '';
  };
}
