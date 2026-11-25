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
            callback.__raw = ''
              (function()
                  local oil_namespace = vim.api.nvim_create_namespace("Oil")
                  local highlight_namespace = vim.api.nvim_create_namespace("OilUntracked")
                  local filename_groups = {
                      OilFile = true, OilFileHidden = true,
                      OilLink = true, OilLinkHidden = true,
                      OilOrphanLink = true, OilOrphanLinkHidden = true,
                  }
                  local attached = {}

                  return function(args)
                      local buf = args.data.buf
                      local dir = require("oil").get_current_dir(buf)
                      if not dir or attached[buf] then
                          return
                      end

                      local state = {}
                      attached[buf] = state
                      local poll, generation = nil, 0
                      local function run_git(command, callback)
                          -- The directory may disappear while Oil is showing it.
                          pcall(vim.system, command, { cwd = dir, timeout = 1000 }, vim.schedule_wrap(callback))
                      end

                      local function refresh()
                          if attached[buf] ~= state then
                              return
                          end
                          generation = generation + 1
                          local request = generation
                          run_git({ "git", "ls-files", "--others", "--exclude-standard", "-z", "--", ":(glob)*" }, function(result)
                              if attached[buf] ~= state or request ~= generation then
                                  return
                              end
                              vim.api.nvim_buf_clear_namespace(buf, highlight_namespace, 0, -1)
                              if result.code ~= 0 or result.stdout == "" then
                                  return
                              end

                              local untracked = {}
                              for name in vim.gsplit(result.stdout, "\0", { plain = true, trimempty = true }) do
                                  untracked[name] = true
                              end

                              -- Reuse the filename ranges Oil rendered so edits and the cursor stay intact.
                              local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                              local marks = vim.api.nvim_buf_get_extmarks(buf, oil_namespace, 0, -1, { details = true })
                              for _, mark in ipairs(marks) do
                                  local _, row, col, details = unpack(mark)
                                  local line = lines[row + 1]
                                  if filename_groups[details.hl_group] and line and details.end_row == row then
                                      local name = line:sub(col + 1, details.end_col):gsub("/$", "")
                                      if untracked[name] then
                                          vim.api.nvim_buf_set_extmark(buf, highlight_namespace, row, col, {
                                              end_col = details.end_col,
                                              hl_group = "OilUntracked",
                                              priority = vim.hl.priorities.user,
                                              invalidate = true,
                                              undo_restore = false,
                                          })
                                      end
                                  end
                              end
                          end)
                      end

                      vim.api.nvim_buf_attach(buf, false, {
                          on_lines = vim.schedule_wrap(function()
                              if attached[buf] == state and poll and not vim.bo[buf].modified then
                                  refresh()
                              end
                          end),
                          on_detach = function()
                              attached[buf] = nil
                              if poll then
                                  poll:close()
                              end
                          end,
                      })

                      -- Resolve the index for this checkout, including linked Git worktrees.
                      run_git({ "git", "rev-parse", "--path-format=absolute", "--git-path", "index" }, function(result)
                          if attached[buf] ~= state or result.code ~= 0 then
                              return
                          end
                          poll = vim.uv.new_fs_poll()
                          if poll then
                              poll:start(result.stdout:gsub("\n$", ""), 1000, vim.schedule_wrap(refresh))
                          end
                          refresh()
                      end)
                  end
              end)()
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
