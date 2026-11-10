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
        DOTFILES_NVIM_LSP_SERVERS = builtins.toJSON neovim.servers;
        nativeBuildInputs = [
          neovim.package
          pkgs.git
          pkgs.ghq
          pkgs.jq
          pkgs.gettext
          pkgs.poppler-utils
          pkgs.fd
          pkgs.ripgrep
          pkgs.lazygit
          pkgs.curl
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        export XDG_CONFIG_HOME="$TMPDIR/config"
        export XDG_DATA_HOME="$TMPDIR/data"
        export XDG_STATE_HOME="$TMPDIR/state"
        export XDG_CACHE_HOME="$TMPDIR/cache"
        mkdir -p "$HOME"
        cd ${files.__path}
        for script in ${scripts."modern.lua"} ${scripts."treesitter.lua"} \
          ${scripts."snacks.lua"} ${scripts."markdown.lua"} ${scripts."keybindings.lua"}; do
          nvim --headless -i NONE \
            -c 'lua for _, name in ipairs(vim.json.decode(vim.env.DOTFILES_NVIM_LSP_SERVERS)) do vim.lsp.enable(name, false) end' \
            -c "lua local ok, err = pcall(dofile, [[$script]]); if not ok then print(err); vim.cmd('cquit 1') end" \
            -c 'qa!'
        done
        touch "$out"
      '';
}
