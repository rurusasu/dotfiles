{
  programs.nixvim =
    { config, lib, ... }:
    {
      config = lib.mkIf config.enable {
        plugins.oil = {
          enable = true;
          settings = {
            default_file_explorer = true;
            delete_to_trash = true;
            watch_for_changes = true;
            view_options.show_hidden = true;
            keymaps."<Esc>" = "actions.close";
          };
        };
        autoGroups.OilOsc7.clear = true;
        autoCmd = [
          {
            event = "User";
            pattern = "OilEnter";
            group = "OilOsc7";
            callback.__raw = ''
              function(args)
                  if args.data.buf ~= vim.api.nvim_get_current_buf() then
                      return
                  end
                  local path = require("oil").get_current_dir(args.data.buf)
                  if path then
                      vim.api.nvim_ui_send(string.format("\27]7;%s\27\\", vim.uri_from_fname(path)))
                  end
              end
            '';
          }
          {
            event = [
              "BufEnter"
              "DirChanged"
            ];
            group = "OilOsc7";
            callback.__raw = ''
              function()
                  if vim.bo.filetype ~= "oil" then
                      return
                  end
                  local path = require("oil").get_current_dir()
                  if path then
                      vim.api.nvim_ui_send(string.format("\27]7;%s\27\\", vim.uri_from_fname(path)))
                  end
              end
            '';
          }
        ];
        keymaps = [
          {
            mode = "n";
            key = "-";
            action = "<cmd>Oil<cr>";
            options.desc = "Open Oil";
          }
        ];
      };
    };
}
