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
      bindkey '\ez' __zoxide_zi_widget
    '';
  };
}
