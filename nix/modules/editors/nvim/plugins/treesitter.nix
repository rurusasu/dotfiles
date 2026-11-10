{
  programs.nixvim =
    { config, lib, ... }:
    {
      config = lib.mkIf config.enable {
        plugins.treesitter = {
          enable = true;
          nixvimInjections = false;
          highlight.enable = true;
          languageRegister = {
            bash = "sh";
            c_sharp = "cs";
            javascript = "javascriptreact";
            tsx = "typescriptreact";
          };
          grammarPackages = with config.plugins.treesitter.package.builtGrammars; [
            bash
            c
            c_sharp
            css
            go
            html
            javascript
            jsdoc
            json
            lua
            markdown
            markdown_inline
            nix
            python
            query
            regex
            rust
            toml
            tsx
            typescript
            vim
            vimdoc
            yaml
          ];
        };
      };
    };
}
