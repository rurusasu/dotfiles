# Native Neovim behavior and the Nix parser/query distribution contract.
{
  fixtures,
  pkgs,
  code,
  files,
}:
{
  neovim-native =
    let
      neovim = code.nix.tests.fixtures.neovim { inherit fixtures pkgs; };
      scripts = files.nix.tests.build.modules.editors.nvim;
    in
    pkgs.runCommand "neovim-native-check"
      {
        nativeBuildInputs = [
          neovim.package
          pkgs.git
          pkgs.jq
          pkgs.gettext
          pkgs.poppler-utils
          pkgs.fd
          pkgs.ripgrep
          pkgs.lazygit
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        export XDG_CONFIG_HOME="$TMPDIR/config"
        export XDG_DATA_HOME="$TMPDIR/data"
        export XDG_STATE_HOME="$TMPDIR/state"
        export XDG_CACHE_HOME="$TMPDIR/cache"
        mkdir -p "$HOME" "$XDG_DATA_HOME/nvim/site/pack"
        ln -s ${neovim.plugins} "$XDG_DATA_HOME/nvim/site/pack/hm"
        mkdir -p "$XDG_CONFIG_HOME/nvim"
        ln -s ${neovim.lua} "$XDG_CONFIG_HOME/nvim/lua"
        cd ${files.__path}
        nvim --headless -u NONE -i NONE -l ${scripts."modern.lua"}
        nvim --headless -u NONE -i NONE -l ${scripts."treesitter.lua"}
        nvim --headless -u NONE -i NONE -l ${scripts."snacks.lua"}
        nvim --headless -i NONE -u ${neovim.init} \
          -c 'lua local ok, err = pcall(dofile, "${scripts."markdown.lua"}"); if not ok then print(err); vim.cmd("cquit 1") end' \
          -c 'qa!'
        nvim --headless -i NONE -u ${neovim.init} \
          -c 'lua local ok, err = pcall(dofile, "${scripts."keybindings.lua"}"); if not ok then print(err); vim.cmd("cquit 1") end' \
          -c 'qa!'
        DOTFILES_NVIM_LSPCONFIG=${pkgs.vimPlugins.nvim-lspconfig} \
          nvim --headless -u NONE -i NONE -l ${scripts."typescript.lua"}
        touch "$out"
      '';
}
