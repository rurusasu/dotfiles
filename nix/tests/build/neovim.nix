# Native Neovim behavior and the Nix parser/query distribution contract.
{ inputs, pkgs }:
let
  neovim = import ../fixtures/neovim.nix { inherit inputs pkgs; };
in
pkgs.runCommand "neovim-native-check"
  {
    nativeBuildInputs = [
      neovim.package
      pkgs.git
      pkgs.jq
      pkgs.gettext
      pkgs.poppler-utils
    ];
  }
  ''
    export XDG_CONFIG_HOME="$TMPDIR/config"
    export XDG_DATA_HOME="$TMPDIR/data"
    export XDG_STATE_HOME="$TMPDIR/state"
    export XDG_CACHE_HOME="$TMPDIR/cache"
    mkdir -p "$XDG_DATA_HOME/nvim/site/pack"
    ln -s ${neovim.plugins} "$XDG_DATA_HOME/nvim/site/pack/hm"
    mkdir -p "$XDG_CONFIG_HOME/nvim"
    ln -s ${neovim.lua} "$XDG_CONFIG_HOME/nvim/lua"
    cd ${../../..}
    nvim --headless -u NONE -i NONE -l tests/lua/nvim_modern_test.lua
    nvim --headless -u NONE -i NONE -l tests/lua/nvim_treesitter_test.lua
    nvim --headless -u NONE -i NONE -l tests/lua/nvim_snacks_test.lua
    nvim --headless -i NONE -u ${neovim.init} \
      -c 'lua local ok, err = pcall(dofile, "tests/lua/nvim_markdown_test.lua"); if not ok then print(err); vim.cmd("cquit 1") end' \
      -c 'qa!'
    DOTFILES_NVIM_LSPCONFIG=${pkgs.vimPlugins.nvim-lspconfig} \
      nvim --headless -u NONE -i NONE -l tests/lua/nvim_typescript_test.lua
    touch "$out"
  ''
