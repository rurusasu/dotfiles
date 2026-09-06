{
  lib,
  neovim,
  vimPlugins,
  symlinkJoin,
}:
let
  languages = builtins.fromJSON (builtins.readFile ../../../chezmoi/dot_config/nvim/treesitter.json);
  parserSet = vimPlugins.nvim-treesitter.withPlugins (
    grammars: map (name: grammars.${name}) languages
  );
  # Keep matching parsers/queries and inherited queries, without loading the
  # nvim-treesitter installer or its Lua runtime inside the editor.
  closure = builtins.genericClosure {
    startSet = map (value: {
      key = toString value;
      inherit value;
    }) parserSet.dependencies;
    operator =
      item:
      map (value: {
        key = toString value;
        inherit value;
      }) (item.value.dependencies or [ ]);
  };
  treesitterRuntime = symlinkJoin {
    name = "dotfiles-neovim-treesitter-runtime";
    paths = map (item: item.value) closure;
  };
in
(neovim.override {
  extraMakeWrapperArgs = lib.escapeShellArgs [
    "--set"
    "DOTFILES_NVIM_TREESITTER"
    treesitterRuntime
  ];
}).overrideAttrs
  (old: {
    passthru = (old.passthru or { }) // {
      inherit languages treesitterRuntime;
    };
  })
