{ config, lib, ... }:
let
  fdOptions = "--hidden --exclude .git";
  followOptions = "${fdOptions} --follow";
in
{
  programs = {
    fzf = {
      fileWidget.zsh.command = "fd --type f ${followOptions}";
      changeDirWidget.zsh.command = "fd --type d ${fdOptions}";
    };

    zsh = {
      # fd ships Zsh completions; the shared Zsh module adds them to fpath.
      shellAliases.find = "fd";
      sessionVariables = lib.mkIf config.programs.fzf.enable {
        FZF_DEFAULT_COMMAND = "fd --type f ${followOptions}";
      };

      # fzf's documented extension points customize its path/directory completion.
      initContent = lib.mkIf config.programs.fzf.enable (
        lib.mkBefore ''
          _fzf_compgen_path() {
            fd ${followOptions} . "$1"
          }
          _fzf_compgen_dir() {
            fd --type d ${followOptions} . "$1"
          }
        ''
      );
    };
  };
}
