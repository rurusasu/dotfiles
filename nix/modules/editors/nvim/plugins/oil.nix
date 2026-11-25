{
  programs.nixvim =
    { config, lib, ... }:
    let
      columns = [ "icon" ];
      detailColumns = columns ++ [
        "permissions"
        "size"
        "mtime"
      ];
    in
    {
      config = lib.mkIf config.enable {
        plugins.oil = {
          enable = true;
          settings = {
            default_file_explorer = true;
            inherit columns;
            delete_to_trash = true;
            watch_for_changes = true;
            view_options = {
              show_hidden = true;
              highlight_filename.__raw = ''
                (function()
                    local cached_buf, cached_tick
                    local untracked = {}

                    return function(entry, _, is_link_target, _, bufnr)
                        if entry.type == "directory" or is_link_target then
                            return
                        end

                        local tick = vim.api.nvim_buf_get_changedtick(bufnr)
                        -- Oil formats every filename before replacing the buffer lines.
                        if bufnr ~= cached_buf or tick ~= cached_tick then
                            cached_buf, cached_tick = bufnr, tick
                            untracked = {}
                            local dir = require("oil").get_current_dir(bufnr)
                            if not dir then
                                return
                            end

                            local ok, process = pcall(vim.system, {
                                "git", "ls-files", "--others", "--exclude-standard", "-z", "--", ":(glob)*",
                            }, { cwd = dir })
                            local result = ok and process:wait(100)
                            if not result or result.code ~= 0 then
                                return
                            end
                            for name in vim.gsplit(result.stdout, "\0", { plain = true, trimempty = true }) do
                                untracked[name] = true
                            end
                        end

                        return untracked[entry.name] and "OilUntracked" or nil
                    end
                end)()
              '';
            };
            keymaps = {
              "<Esc>" = "actions.close";
              gy = {
                __unkeyed-1 = "actions.yank_entry";
                opts.modify = ":.";
                mode = "n";
              };
              gd = {
                desc = "Toggle file details";
                mode = "n";
                callback.__raw = ''
                  function()
                      local simple = ${lib.generators.toLua { } columns}
                      local detailed = ${lib.generators.toLua { } detailColumns}
                      local current = require("oil.config").columns
                      require("oil").set_columns(vim.deep_equal(current, detailed) and simple or detailed)
                  end
                '';
              };
            };
          };
        };
        colorschemes.catppuccin.settings.custom_highlights.OilUntracked.link = "Directory";
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
