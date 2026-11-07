# Neovim lhs syntax retains leader sequences in the export.
let
  bind = action: key: {
    inherit action key;
    mode = "n";
    scope = "editor";
  };
in
[
  (bind "which-key" "<leader>")
  (bind "smart-files" "<leader><leader>")
  (bind "git" "<leader>gg")
  (bind "files" "<leader>sg")
  (bind "window-next" "<C-w>w")
  (bind "width-minus" "<C-Left>")
  (bind "width-plus" "<C-Right>")
  (bind "buffer-prev" "<S-h>")
  (bind "buffer-next" "<S-l>")
  (bind "buffer-delete" "<leader>bd")
]
