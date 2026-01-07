# zsh profile - uses settings from myHomeSettings.fd and myHomeSettings.fzf
{
  pkgs,
  config,
  lib,
  ...
}:
with lib;
let
  fdCfg = config.myHomeSettings.fd;
  fzfCfg = config.myHomeSettings.fzf;

  # Build fd options string (same as fzf profile)
  fdOptions =
    (optional fdCfg.hidden "--hidden")
    ++ (optional fdCfg.followSymlinks "--follow")
    ++ (optional fdCfg.noIgnoreVcs "--no-ignore-vcs")
    ++ (optional (fdCfg.maxResults != null) "--max-results=${toString fdCfg.maxResults}")
    ++ (optional (fdCfg.maxDepth != null) "--max-depth=${toString fdCfg.maxDepth}")
    ++ fdCfg.extraOptions;

  fdOptionsStr = concatStringsSep " " fdOptions;
  searchRoot = fzfCfg.searchRoot;
in
{
  programs.zsh = {
    enable = true;
    shellAliases = {
      nrs = "sudo nixos-rebuild switch --flake ~/.dotfiles --impure";
      nrt = "sudo nixos-rebuild test --flake ~/.dotfiles --impure";
      nrb = "sudo nixos-rebuild boot --flake ~/.dotfiles --impure";
      find = "fd";
      grep = "rg";
      # k3s aliases (no sudo needed)
      k = "kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml";
      kgn = "kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml get nodes";
      kgp = "kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml get pods -A";
      kgs = "kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml get svc -A";
      cilium = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml cilium";
      k3s-status = "systemctl status k3s";
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
        dir="$(${pkgs.fd}/bin/fd ${fdOptionsStr} -t d . ${searchRoot} | ${pkgs.fzf}/bin/fzf)" && cd "$dir"
        zle reset-prompt
      }
      zle -N __fzf_cd_widget
      bindkey '^[d' __fzf_cd_widget  # Alt+D

      # Alt+T: fzf file/directory search and insert
      __fzf_file_widget() {
        local selected
        selected="$(${pkgs.fd}/bin/fd ${fdOptionsStr} . ${searchRoot} | ${pkgs.fzf}/bin/fzf)"
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

      # k3s KUBECONFIG environment variable
      export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    '';
  };
}
