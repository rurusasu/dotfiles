{
  programs.nixvim =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      columns = [ "icon" ];
      detailColumns = columns ++ [
        "permissions"
        "size"
        "mtime"
      ];
    in
    {
      imports = [
        (lib.nixvim.plugins.mkNeovimPlugin {
          name = "oil-git";
          maintainers = [ ];
          configLocation = lib.mkOrder 1100 "extraConfigLua";
          package = lib.mkOption {
            type = lib.types.package;
            default = pkgs.vimUtils.buildVimPlugin {
              name = "oil-git.nvim";
              src = pkgs.fetchFromGitHub {
                owner = "malewicz1337";
                repo = "oil-git.nvim";
                rev = "8bab14df0b7db7a62fa75c8978d6181daed2f0a2";
                hash = "sha256-JqJ1t4Zk4ROUXnFvk63hJw18nq7rXQU5NxnP4HHWXpU=";
              };
            };
          };
        })
      ];
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
        plugins.oil-git = {
          enable = true;
          settings = {
            show_directory_highlights = false;
            symbol_position = "none";
          };
        };
        colorschemes.catppuccin.settings.custom_highlights =
          lib.genAttrs
            [
              "OilGitAdded"
              "OilGitModifiedStaged"
              "OilGitModifiedUnstaged"
              "OilGitRenamed"
              "OilGitDeleted"
              "OilGitCopied"
              "OilGitConflict"
            ]
            (_: {
              link = "NONE";
            })
          // {
            OilGitUntracked.link = "Directory";
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
