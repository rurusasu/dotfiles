# Native Neovim behavior and the Nix parser/query distribution contract.
{ inputs, pkgs }:
let
  neovim = import ../fixtures/neovim.nix { inherit inputs pkgs; };
  customXdgNeovim = import ../fixtures/neovim.nix {
    inherit inputs pkgs;
    configDirectory = ".custom config";
  };
in
pkgs.runCommand "neovim-native-check"
  {
    nativeBuildInputs = [
      neovim.package
      pkgs.git
      pkgs.jq
      pkgs.python3
      pkgs.gettext
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
    python3 -m unittest discover -s tests/python -p test_neovim_migration.py -v
    bash tests/bash/neovim_home_manager_activation.sh ${neovim.fileActivation} ${neovim.homeFiles}
    bash tests/bash/neovim_home_manager_activation.sh ${customXdgNeovim.fileActivation} ${customXdgNeovim.homeFiles} '.custom config'
    nvim --headless -u NONE -i NONE -l tests/lua/nvim_modern_test.lua
    nvim --headless -u NONE -i NONE -l tests/lua/nvim_treesitter_test.lua
    nvim --headless -i NONE -u ${neovim.init} \
      -c 'lua local ok, err = pcall(dofile, "tests/lua/nvim_markdown_test.lua"); if not ok then print(err); vim.cmd("cquit 1") end' \
      -c 'qa!'
    DOTFILES_NVIM_LSPCONFIG=${pkgs.vimPlugins.nvim-lspconfig} \
      nvim --headless -u NONE -i NONE -l tests/lua/nvim_typescript_test.lua
    # Remote 設定は JSON5 の既存キーを保持し、壊れたファイルは変更しない。
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME/.cursor-server/data/Machine"
    settings_file="$HOME/.cursor-server/data/Machine/settings.json"
    printf '%s\n' '{ "unrelated": true, "nix.serverPath": "old", /* keep */ }' > "$settings_file"
    ${neovim.cursorRemoteActivation}
    jq -e '.unrelated == true and .["nix.serverPath"] == "nixd" and .["ruff.path"] == ["ruff"]' "$settings_file"
    ${neovim.cursorRemoteActivation}
    printf '%s\n' 'invalid JSON' > "$settings_file"
    if ${neovim.cursorRemoteActivation}; then
      echo 'Invalid Remote settings must fail without overwriting them' >&2
      exit 1
    fi
    test "$(cat "$settings_file")" = 'invalid JSON'
    echo 'Cursor Remote settings preserve unrelated keys and reject invalid input'
    touch "$out"
  ''
