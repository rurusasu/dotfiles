{
  programs.nixvim =
    { config, lib, ... }:
    {
      config = lib.mkIf config.enable {
        plugins.sidekick = {
          enable = true;
          settings = {
            # Copilot NES は未構成。Sidekick は AI CLI の操作に使う。
            nes.enabled = false;
            cli = {
              mux.enabled = false;
              win = {
                layout = "right";
                wo.wrap = true;
                config.__raw = ''
                  function(terminal)
                      local function wrap()
                          if terminal.win and vim.api.nvim_win_is_valid(terminal.win) then
                              vim.wo[terminal.win].wrap = require("sidekick.config").cli.win.wo.wrap
                          end
                      end
                      vim.api.nvim_create_autocmd({ "TermOpen", "BufWinEnter", "BufEnter", "WinEnter" }, {
                          group = terminal.group,
                          callback = function(args)
                              if
                                  terminal.win
                                  and vim.api.nvim_win_is_valid(terminal.win)
                                  and vim.api.nvim_win_get_buf(terminal.win) == args.buf
                              then
                                  vim.schedule(wrap)
                              end
                          end,
                      })
                  end
                '';
              };
            };
          };
        };
        keymaps = [
          {
            mode = [
              "n"
              "t"
              "i"
              "x"
            ];
            key = "<C-.>";
            action.__raw = ''function() require("sidekick.cli").focus() end'';
            options.desc = "Sidekick focus";
          }
          {
            mode = "n";
            key = "<leader>as";
            action.__raw = ''function() require("sidekick.cli").select({ focus = true }) end'';
            options.desc = "Sidekick select CLI";
          }
          {
            mode = "n";
            key = "<leader>ad";
            action.__raw = ''function() require("sidekick.cli").close() end'';
            options.desc = "Sidekick detach CLI";
          }
          {
            mode = [
              "x"
              "n"
            ];
            key = "<leader>at";
            action.__raw = ''function() require("sidekick.cli").send({ msg = "{this}" }) end'';
            options.desc = "Sidekick send this";
          }
          {
            mode = "n";
            key = "<leader>af";
            action.__raw = ''function() require("sidekick.cli").send({ msg = "{file}" }) end'';
            options.desc = "Sidekick send file";
          }
          {
            mode = "x";
            key = "<leader>av";
            action.__raw = ''function() require("sidekick.cli").send({ msg = "{selection}" }) end'';
            options.desc = "Sidekick send selection";
          }
          {
            mode = [
              "n"
              "x"
            ];
            key = "<leader>ap";
            action.__raw = ''function() require("sidekick.cli").prompt() end'';
            options.desc = "Sidekick prompt library";
          }
        ];
      };
    };
}
