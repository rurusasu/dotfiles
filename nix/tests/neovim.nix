# Native Neovim behavior and the Nix parser/query distribution contract.
{ pkgs }:
let
  neovim = pkgs.callPackage ../packages/neovim { };
in
pkgs.runCommand "neovim-native-check" { nativeBuildInputs = [ neovim ]; } ''
  export XDG_CONFIG_HOME="$TMPDIR/config"
  export XDG_DATA_HOME="$TMPDIR/data"
  export XDG_STATE_HOME="$TMPDIR/state"
  export XDG_CACHE_HOME="$TMPDIR/cache"
  cd ${../..}
  nvim --headless -u NONE -i NONE -l tests/lua/nvim_modern_test.lua
  nvim --headless -u NONE -i NONE -l tests/lua/nvim_treesitter_test.lua
  nvim --headless -u NONE -i NONE -l tests/lua/nvim_treesitter_installer_test.lua
  DOTFILES_NVIM_LSPCONFIG=${pkgs.vimPlugins.nvim-lspconfig} \
    nvim --headless -u NONE -i NONE -l tests/lua/nvim_typescript_test.lua
  touch "$out"
''
