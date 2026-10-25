# Neovim lhs syntax retains leader sequences and Oil's local scope in the export.
let
  bind = action: key: {
    inherit action key;
    mode = "n";
    scope = "editor";
  };
  oil = action: key: (bind action key) // { scope = "oil"; };
in
[
  (bind "which-key" "<leader>")
  (bind "smart-files" "<leader><leader>")
  (bind "explorer" "<leader>e")
  (bind "git" "<leader>gg")
  (bind "files" "<leader>sg")
  (bind "window-next" "<C-w>w")
  (bind "width-minus" "<C-Left>")
  (bind "width-plus" "<C-Right>")
  (bind "buffer-prev" "<S-h>")
  (bind "buffer-next" "<S-l>")
  (bind "buffer-delete" "<leader>bd")
  (oil "oil-add-file" "a")
  (oil "oil-add-dir" "A")
  (oil "oil-delete" "d")
  (oil "oil-move" "m")
  (oil "oil-rename" "r")
  (oil "oil-help" "?")
]
