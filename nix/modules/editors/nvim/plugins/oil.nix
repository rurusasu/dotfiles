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
            view_options.show_hidden = true;
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
        autoGroups.OilGit.clear = true;
        autoGroups.OilOsc7.clear = true;
        autoCmd = [
          {
            event = "User";
            pattern = "OilEnter";
            group = "OilGit";
            once = true;
            callback.__raw = ''
              function()
                  local oil = require("oil")
                  local oil_marks = vim.api.nvim_create_namespace("Oil")
                  local git_marks = vim.api.nvim_create_namespace("OilUntracked")
                  local filename_groups = { OilFile = true, OilLink = true, OilOrphanLink = true }
                  local running = {}

                  local function paint(buf, result)
                      vim.api.nvim_buf_clear_namespace(buf, git_marks, 0, -1)
                      if result.code ~= 0 or result.stdout == "" then
                          return
                      end
                      local untracked = {}
                      for name in vim.gsplit(result.stdout, "\0", { plain = true, trimempty = true }) do
                          untracked[name] = true
                      end
                      -- Use Oil's filename ranges so refreshing never rewrites the buffer.
                      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, oil_marks, 0, -1, { details = true })) do
                          local _, row, col, details = unpack(mark)
                          local group = (details.hl_group or ""):gsub("Hidden$", "")
                          local line = lines[row + 1]
                          if filename_groups[group] and line and row == details.end_row
                              and untracked[line:sub(col + 1, details.end_col):gsub("/$", "")]
                          then
                              vim.api.nvim_buf_set_extmark(buf, git_marks, row, col, {
                                  end_col = details.end_col,
                                  hl_group = "OilUntracked",
                                  priority = vim.hl.priorities.user,
                                  invalidate = true,
                                  undo_restore = false,
                              })
                          end
                      end
                  end

                  local function poll()
                      vim.defer_fn(poll, 1000)
                      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                          local buf = vim.api.nvim_win_get_buf(win)
                          local dir = vim.bo[buf].filetype == "oil" and oil.get_current_dir(buf)
                          if dir and not running[buf] and vim.fs.root(dir, ".git") then
                              local started = pcall(vim.system,
                                  { "git", "ls-files", "--others", "--exclude-standard", "-z", "--", ":(glob)*" },
                                  { cwd = dir, timeout = 750 },
                                  vim.schedule_wrap(function(result)
                                      running[buf] = nil
                                      if vim.api.nvim_buf_is_loaded(buf) and oil.get_current_dir(buf) == dir then
                                          paint(buf, result)
                                      end
                                  end))
                              running[buf] = started or nil
                          end
                      end
                  end
                  poll()
              end
            '';
          }
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
