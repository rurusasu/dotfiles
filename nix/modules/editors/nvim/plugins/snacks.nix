{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages =
    lib.mkIf (config.programs.nixvim.enable && config.programs.nixvim.plugins.snacks.enable)
      [
        pkgs.neovim-remote
        pkgs.imagemagick
        pkgs.poppler-utils
      ];
  programs.lazydocker.enable = lib.mkIf (
    config.programs.nixvim.enable && config.programs.nixvim.plugins.snacks.enable
  ) true;
  programs.nixvim =
    { config, lib, ... }:
    let
      lazygit = log: ''
        function()
            local log = ${lib.boolToString log}
            local Snacks = require("snacks")
            local root = Snacks.git.get_root()
            if not root then
                if not log then
                    vim.notify("lazygit: not in a git repository", vim.log.levels.WARN)
                end
                return
            end
            local open = log and Snacks.lazygit.log or Snacks.lazygit.open
            open({ cwd = root })
        end
      '';
    in
    {
      config = lib.mkIf config.enable {
        dependencies.git.enable = false;
        plugins.snacks = {
          enable = true;
          settings = {
            lazygit.enabled = true;
            terminal = {
              enabled = true;
              win = {
                keys.term_normal = false;
                wo = {
                  wrap = true;
                  sidescrolloff = 0;
                };
                on_buf.__raw = ''
                  function(terminal)
                      vim.api.nvim_create_autocmd("TermOpen", {
                          buffer = terminal.buf,
                          callback = function()
                              for _, win in ipairs(vim.fn.win_findbuf(terminal.buf)) do
                                  vim.wo[win].wrap = terminal.opts.wo.wrap
                                  vim.wo[win].sidescrolloff = terminal.opts.wo.sidescrolloff
                              end
                          end,
                      })
                  end
                '';
              };
            };
            image = {
              enabled = true;
              convert.notify = true;
              formats.__raw = ''
                vim.tbl_filter(function(format) return format ~= "pdf" end, require("snacks").config.image.formats)
              '';
            };
            picker = {
              enabled = true;
              preview.__raw = ''
                function(ctx)
                    local preview = require("snacks.picker.preview")
                    local file = require("snacks").picker.util.path(ctx.item) or (ctx.item and ctx.item.path)
                    if not file or not file:match("%.pdf$") then
                        return preview.file(ctx)
                    end
                    if vim.fn.executable("pdftoppm") == 0 then
                        vim.notify("PDF preview requires Poppler (pdftoppm). See docs/chezmoi/neovim.md.", vim.log.levels.WARN)
                        return false
                    end
                    local tmp = vim.fn.tempname()
                    local result = vim.system({ "pdftoppm", "-png", "-r", "150", "-singlefile", file, tmp }, { text = true })
                        :wait(10000)
                    if result.code ~= 0 then
                        vim.fn.delete(tmp .. ".png")
                        vim.notify("PDF conversion failed: " .. (result.stderr or tostring(result.code)), vim.log.levels.WARN)
                        return false
                    end
                    tmp = tmp .. ".png"
                    return preview.image(vim.tbl_extend("force", ctx, {
                        item = vim.tbl_extend("force", ctx.item, { file = tmp, _path = tmp }),
                    }))
                end
              '';
              config.__raw = ''
                function(opts)
                    local preview_file = require("snacks").config.picker.preview
                    if not opts.multi or opts.preview ~= preview_file then
                        return
                    end
                    opts.preview = nil
                    for i, source in ipairs(opts.multi) do
                        source = type(source) == "string" and { source = source } or source
                        local preset = opts.sources[source.source] or {}
                        local preview = source.preview or preset.preview
                        if not preview or preview == "file" then
                            opts.multi[i] = vim.tbl_extend("force", source, { preview = preview_file })
                        end
                    end
                end
              '';
              actions.sidekick_send.__raw = ''
                function(...) return require("sidekick.cli.picker.snacks").send(...) end
              '';
              win.input.keys."<a-a>" = {
                __unkeyed-1 = "sidekick_send";
                mode = [
                  "n"
                  "i"
                ];
              };
            };
          };
        };
        keymaps = [
          {
            mode = "n";
            key = "<leader>ff";
            action.__raw = ''function() require("snacks").picker.files() end'';
            options.desc = "Find files";
          }
          {
            mode = "n";
            key = "<leader>fg";
            action.__raw = ''function() require("snacks").picker.grep() end'';
            options.desc = "Live grep";
          }
          {
            mode = "n";
            key = "<leader>fb";
            action.__raw = ''function() require("snacks").picker.buffers() end'';
            options.desc = "Buffers";
          }
          {
            mode = "n";
            key = "<leader>fq";
            action.__raw = ''
              function()
                  local Snacks = require("snacks")
                  if vim.fn.executable("ghq") == 0 then
                      vim.notify("ghq not found", vim.log.levels.WARN)
                      return
                  end
                  Snacks.picker({
                      finder = "proc",
                      format = "file",
                      cmd = "ghq",
                      args = { "list", "--full-path" },
                      title = "ghq repos",
                      transform = function(item)
                          item.file = item.text
                          return item
                      end,
                      confirm = function(picker, item)
                          picker:close()
                          if item and item.file then
                              vim.cmd.cd(item.file)
                          end
                      end,
                  })
              end
            '';
            options.desc = "ghq repos";
          }
          {
            mode = "n";
            key = "<leader><leader>";
            action.__raw = ''
              function()
                  local Snacks = require("snacks")
                  local sources = require("snacks.picker.config.sources")
                  local files = Snacks.git.get_root() == nil and sources.files
                      or vim.tbl_deep_extend("force", sources.git_files, {
                          untracked = true,
                          cwd = vim.uv.cwd(),
                      })
                  Snacks.picker({
                      multi = { "buffers", "recent", files },
                      format = "file",
                      matcher = { frecency = true, sort_empty = true },
                      filter = { cwd = true },
                      transform = "unique_file",
                  })
              end
            '';
            options.desc = "Find files (smart)";
          }
          {
            mode = "n";
            key = "<leader>sg";
            action.__raw = ''function() require("snacks").picker.files() end'';
            options.desc = "Open file";
          }
          {
            mode = "n";
            key = "<leader>gg";
            action.__raw = lazygit false;
            options.desc = "Lazygit";
          }
          {
            mode = "n";
            key = "<leader>gl";
            action.__raw = lazygit true;
            options.desc = "Git log";
          }
          {
            mode = "n";
            key = "<leader>gf";
            action.__raw = ''function() require("snacks").lazygit.log_file() end'';
            options.desc = "Git log (file)";
          }
          {
            mode = "n";
            key = "<leader>dc";
            action.__raw = ''function() require("snacks").terminal.toggle({ "lazydocker" }, { win = { position = "float" } }) end'';
            options.desc = "Lazydocker";
          }
          {
            mode = "n";
            key = "<leader>tt";
            action.__raw = ''function() require("snacks").terminal.toggle(nil, { win = { position = "bottom", height = 0.3 } }) end'';
            options.desc = "Toggle bottom terminal";
          }
          {
            mode = "n";
            key = "<leader>tf";
            action.__raw = ''function() Snacks.terminal.toggle({ vim.o.shell }, { win = { position = "float" } }) end'';
            options.desc = "Toggle floating terminal";
          }
        ];
      };
    };
}
