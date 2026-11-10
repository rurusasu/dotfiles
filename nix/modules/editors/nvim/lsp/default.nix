_: {
  programs.nixvim = { config, lib, ... }: {
    config = lib.mkIf config.enable {
      extraConfigLuaPre = lib.mkOrder 650 ''
        local function format_lsp_buffer(buf, async)
            if vim.bo[buf].buftype ~= "" or not vim.bo[buf].modifiable then
                return
            end
            local clients = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/formatting" })
            table.sort(clients, function(a, b)
                return a.id < b.id
            end)
            local preferred = (vim.g.dotfiles_formatters or {})[vim.bo[buf].filetype]
            for _, client in ipairs(clients) do
                if not preferred or client.name == preferred then
                    vim.lsp.buf.format({ bufnr = buf, id = client.id, async = async, timeout_ms = 3000 })
                    return
                end
            end
        end
      '';
      globals.dotfiles_formatters = {
        python = "ruff";
        rust = "rust_analyzer";
      };
      lsp = {
        # LSP 本体は runtime/default.nix が通常のユーザー PATH に導入する。
        servers = {
          nixd = {
            enable = true;
            package = null;
            config.settings.nixd.formatting.command = [ "nixfmt" ];
          };
          gopls = {
            enable = true;
            package = null;
            config.settings.gopls.gofumpt = true;
          };
          rust_analyzer = {
            enable = true;
            package = null;
            config.settings.rust-analyzer = {
              checkOnSave = true;
              check = {
                command = "clippy";
                allTargets = true;
                extraArgs = [
                  "--locked"
                  "--offline"
                ];
              };
            };
          };
          yamlls = {
            enable = true;
            package = null;
            config.settings.yaml.format.enable = true;
          };
          csharp_ls = {
            enable = true;
            package = null;
          };
          oxlint = {
            enable = true;
            package = null;
          };
          taplo = {
            enable = true;
            package = null;
          };
          bashls = {
            enable = true;
            package = null;
          };
          lua_ls = {
            enable = true;
            package = null;
          };
          tsc = {
            enable = true;
            package = null;
          };
          marksman = {
            enable = true;
            package = null;
          };
          ruff = {
            enable = true;
            package = null;
            # hover は併用する ty に任せる（Ruff 公式の併用例）。
            config.on_attach.__raw = ''
              function(client)
                client.server_capabilities.hoverProvider = false
              end
            '';
          };
          ty = {
            enable = true;
            package = null;
          };
        };
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
            action.__raw = "function() format_lsp_buffer(0, true) end";
            options.desc = "Format";
          }
        ];
      };
      autoGroups.DotfilesLsp.clear = true;
      autoCmd = [
        {
          event = "BufWritePre";
          group = "DotfilesLsp";
          callback.__raw = "function(args) format_lsp_buffer(args.buf, false) end";
        }
      ];
    };
  };
}
