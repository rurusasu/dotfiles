{
  imports = [
    ./bashls.nix
    ./csharp_ls.nix
    ./gopls.nix
    ./lua_ls.nix
    ./marksman.nix
    ./nixd.nix
    ./oxlint.nix
    ./powershell_es.nix
    ./ruff.nix
    ./rust_analyzer.nix
    ./taplo.nix
    ./tsc.nix
    ./ty.nix
    ./yamlls.nix
  ];
  programs.nixvim = { config, lib, ... }: {
    config = lib.mkIf config.enable {
      lsp = {
        completion = {
          enable = true;
          settings.autotrigger = true;
        };
        keymaps = [
          {
            key = "gd";
            lspBufAction = "definition";
            options.desc = "Go to definition";
          }
          {
            key = "<leader>rn";
            lspBufAction = "rename";
            options.desc = "Rename";
          }
          {
            key = "<leader>ca";
            lspBufAction = "code_action";
            options.desc = "Code action";
          }
          {
            key = "<leader>f";
            lspBufAction = "format";
            options.desc = "Format";
          }
        ];
      };
      autoGroups.DotfilesLsp.clear = true;
      autoCmd = [
        {
          event = "BufWritePre";
          group = "DotfilesLsp";
          command = "lua vim.lsp.buf.format({ timeout_ms = 10000 })";
        }
      ];
    };
  };
}
