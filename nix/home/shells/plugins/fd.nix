{ lib, ... }:
let
  fdOptions = "--hidden --exclude .git";
  followOptions = "${fdOptions} --follow";
in
{
  # fd ships Zsh completions; the shared Zsh module adds them to fpath.
  # There is no separate init command or enableZshIntegration option for fd.
  programs.zsh.shellAliases.find = "fd";

  programs.zsh.initContent = lib.mkBefore ''
    if command -v fzf >/dev/null 2>&1; then
      export FZF_DEFAULT_COMMAND='fd --type f ${followOptions}'
      export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
      export FZF_ALT_C_COMMAND='fd --type d ${fdOptions}'

      _fzf_compgen_path() {
        fd ${followOptions} . "$1"
      }
      _fzf_compgen_dir() {
        fd --type d ${followOptions} . "$1"
      }
    fi
  '';
}
