{ inputs, ... }:
{
  programs.nixvim =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      applyHighlights = ''
        function()
            for name, style in pairs(vim.g.dotfiles_highlights or {}) do
                vim.api.nvim_set_hl(0, name, style)
            end
        end
      '';
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
            if vim.fn.has("win32") == 1 then
                float_term.toggle({
                    id = log and "lazygit-log" or "lazygit",
                    cmd = log and { "lazygit", "log" } or { "lazygit" },
                    cwd = root,
                    env = { NVIM = "" },
                })
            else
                local open = log and Snacks.lazygit.log or Snacks.lazygit.open
                open({ cwd = root })
            end
        end
      '';
      inclineColors = {
        fg = "#c0caf5";
        dim = "#565f89";
        error = "#f7768e";
        warn = "#e0af68";
        info = "#7dcfff";
      };
    in
    {
      imports = [
        (lib.nixvim.plugins.mkNeovimPlugin {
          name = "modes";
          maintainers = [ ];
          package = lib.mkOption {
            type = lib.types.package;
            default = pkgs.vimUtils.buildVimPlugin {
              name = "modes.nvim";
              src = inputs.modes-nvim;
            };
          };
        })
        (lib.nixvim.plugins.mkNeovimPlugin {
          name = "incline";
          maintainers = [ ];
          package = "incline-nvim";
        })
      ];
      config = lib.mkIf config.enable {
        dependencies.git.enable = false;
        globals = {
          dotfiles_incline_colors = inclineColors;
          dotfiles_highlights = {
            RainbowRed.fg = "#E06C75";
            RainbowYellow.fg = "#E5C07B";
            RainbowBlue.fg = "#61AFEF";
            RainbowOrange.fg = "#D19A66";
            RainbowGreen.fg = "#98C379";
            RainbowViolet.fg = "#C678DD";
            RainbowCyan.fg = "#56B6C2";
            InclineActive = {
              bg = "#2d2f3f";
              inherit (inclineColors) fg;
            };
            InclineInactive = {
              bg = "#2d2f3f";
              fg = inclineColors.dim;
            };
          };
        };
        autoGroups.DotfilesHighlights.clear = true;
        autoCmd = [
          {
            event = "ColorScheme";
            group = "DotfilesHighlights";
            callback.__raw = applyHighlights;
          }
        ];
        plugins = {
          treesitter = {
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
          web-devicons.enable = true;
          oil = {
            enable = true;
            settings = {
              default_file_explorer = true;
              delete_to_trash = true;
              watch_for_changes = true;
              view_options.show_hidden = true;
              keymaps."<Esc>" = "actions.close";
            };
          };
          gitsigns.enable = true;
          which-key = {
            enable = true;
            settings.triggers = [
              {
                __unkeyed-1 = "<auto>";
                mode = "nixsotc";
              }
              {
                __unkeyed-1 = "<leader>";
                mode = "n";
              }
            ];
          };
          nvim-autopairs = {
            enable = true;
            settings.map_cr = false;
          };
          nvim-surround.enable = true;
          indent-blankline = {
            enable = true;
            settings.indent.highlight = [
              "RainbowRed"
              "RainbowYellow"
              "RainbowBlue"
              "RainbowOrange"
              "RainbowGreen"
              "RainbowViolet"
              "RainbowCyan"
            ];
            luaConfig.pre = ''
              local hooks = require("ibl.hooks")
              hooks.register(hooks.type.HIGHLIGHT_SETUP, ${applyHighlights})
            '';
          };
          modes = {
            enable = true;
            settings = {
              colors = {
                copy = "#f9e2af";
                delete = "#f38ba8";
                insert = "#89dceb";
                visual = "#cba6f7";
              };
              line_opacity = {
                copy = 0.4;
                delete = 0.4;
                insert = 0.4;
                visual = 0.4;
              };
            };
          };
          incline = {
            enable = true;
            luaConfig.pre = "do (${applyHighlights})() end";
            settings = {
              window = {
                padding = 1;
                margin = {
                  horizontal = 1;
                  vertical = 0;
                };
                placement = {
                  horizontal = "right";
                  vertical = "bottom";
                };
                winhighlight = {
                  active.Normal = "InclineActive";
                  inactive.Normal = "InclineInactive";
                };
                options.winblend = 0;
              };
              render.__raw = ''
                function(props)
                    local devicons = require("nvim-web-devicons")
                    local c = vim.g.dotfiles_incline_colors

                    local bufnr = props.buf
                    if vim.bo[bufnr].buftype == "terminal" then
                        return false
                    end
                    local focused = props.focused
                    local fname = vim.api.nvim_buf_get_name(bufnr)
                    local tail = fname ~= "" and vim.fn.fnamemodify(fname, ":t") or "[No Name]"

                    local icon, icon_color
                    if fname ~= "" then
                        icon, icon_color = devicons.get_icon_color(tail, vim.fn.fnamemodify(fname, ":e"), { default = true })
                    end
                    icon = icon or " "
                    icon_color = (focused and icon_color) or c.dim

                    local result = {}
                    if focused then
                        local diag_specs = {
                            { vim.diagnostic.severity.ERROR, "⊘", c.error },
                            { vim.diagnostic.severity.WARN, "△", c.warn },
                            { vim.diagnostic.severity.INFO, "⊙", c.info },
                        }
                        local any = false
                        local counts = vim.diagnostic.count(bufnr)
                        for _, spec in ipairs(diag_specs) do
                            local count = counts[spec[1]] or 0
                            if count > 0 then
                                result[#result + 1] = { spec[2] .. " " .. count .. " ", guifg = spec[3] }
                                any = true
                            end
                        end
                        if any then
                            result[#result + 1] = { "| ", guifg = c.dim }
                        end
                    end

                    result[#result + 1] = { icon .. " ", guifg = icon_color }
                    result[#result + 1] = { tail, guifg = focused and c.fg or c.dim }
                    if vim.bo[bufnr].modified then
                        result[#result + 1] = { " ●", guifg = c.warn }
                    end
                    return result
                end
              '';
            };
          };
          lspconfig.enable = true;
          snacks = {
            enable = true;
            luaConfig.pre = ''
              vim.fn.mkdir(vim.fn.stdpath("cache"), "p")
              local function preview_file(ctx)
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
                preview.__raw = "preview_file";
                config.__raw = ''
                  function(opts)
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
          sidekick = {
            enable = true;
            luaConfig.pre = ''
              local function resize_sidekick(terminal, delta)
                  local win = terminal and terminal.win
                  if not win or not vim.api.nvim_win_is_valid(win) then
                      return
                  end

                  local layout = terminal.opts and terminal.opts.layout or "right"
                  if layout == "float" then
                      local cfg = vim.api.nvim_win_get_config(win)
                      cfg.width = math.max(20, (cfg.width or vim.api.nvim_win_get_width(win)) + delta)
                      cfg.height = math.max(5, (cfg.height or vim.api.nvim_win_get_height(win)) + delta)
                      vim.api.nvim_win_set_config(win, cfg)
                  elseif layout == "top" or layout == "bottom" then
                      vim.api.nvim_win_set_height(win, math.max(5, vim.api.nvim_win_get_height(win) + delta))
                  else
                      vim.api.nvim_win_set_width(win, math.max(20, vim.api.nvim_win_get_width(win) + delta))
                  end
              end
              local function resize_sidekick_toward(terminal, direction)
                  local layout = terminal.opts and terminal.opts.layout or "right"
                  if layout == "top" or layout == "bottom" then
                      return
                  end

                  local delta = direction == "left" and 5 or -5
                  if layout == "left" then
                      delta = -delta
                  end
                  resize_sidekick(terminal, delta)
              end
            '';
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
                  keys = {
                    resize_grow = {
                      __unkeyed-1 = "<M-+>";
                      __unkeyed-2.__raw = "function(t) resize_sidekick(t, 5) end";
                      mode = "nt";
                      desc = "Sidekick grow window";
                    };
                    resize_shrink = {
                      __unkeyed-1 = "<M-_>";
                      __unkeyed-2.__raw = "function(t) resize_sidekick(t, -5) end";
                      mode = "nt";
                      desc = "Sidekick shrink window";
                    };
                    resize_left = {
                      __unkeyed-1 = "<C-S-h>";
                      __unkeyed-2.__raw = ''function(t) resize_sidekick_toward(t, "left") end'';
                      mode = "nt";
                      desc = "Sidekick resize left";
                    };
                    resize_right = {
                      __unkeyed-1 = "<C-S-l>";
                      __unkeyed-2.__raw = ''function(t) resize_sidekick_toward(t, "right") end'';
                      mode = "nt";
                      desc = "Sidekick resize right";
                    };
                  };
                };
              };
            };
          };
          render-markdown.enable = true;
        };
        keymaps = [
          {
            mode = "n";
            key = "-";
            action = "<cmd>Oil<cr>";
            options.desc = "Open Oil";
          }
          {
            mode = "n";
            key = "<leader>mp";
            action.__raw = ''function() require("render-markdown").toggle() end'';
            options.desc = "Toggle Markdown rendering";
          }
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
            action.__raw = "function() float_term.toggle() end";
            options.desc = "Toggle floating terminal";
          }
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
