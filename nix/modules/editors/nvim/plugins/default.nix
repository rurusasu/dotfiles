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
            callback.__raw = "Dotfiles.highlights";
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
              hooks.register(hooks.type.HIGHLIGHT_SETUP, Dotfiles.highlights)
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
            luaConfig.pre = "Dotfiles.highlights()";
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
              render.__raw = "Dotfiles.incline.render";
            };
          };
          lspconfig.enable = true;
          snacks = {
            enable = true;
            luaConfig.pre = ''vim.fn.mkdir(vim.fn.stdpath("cache"), "p")'';
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
                  on_buf.__raw = "Dotfiles.snacks.terminal_on_buf";
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
                preview.__raw = "Dotfiles.snacks_picker.preview_file";
                config.__raw = "Dotfiles.snacks_picker.configure_previews";
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
            settings = {
              # Copilot NES は未構成。Sidekick は AI CLI の操作に使う。
              nes.enabled = false;
              cli = {
                mux.enabled = false;
                win = {
                  layout = "right";
                  wo.wrap = true;
                  config.__raw = "Dotfiles.sidekick.configure_terminal";
                  keys = {
                    resize_grow = {
                      __unkeyed-1 = "<M-+>";
                      __unkeyed-2.__raw = "function(t) Dotfiles.sidekick.resize_cli(t, 5) end";
                      mode = "nt";
                      desc = "Sidekick grow window";
                    };
                    resize_shrink = {
                      __unkeyed-1 = "<M-_>";
                      __unkeyed-2.__raw = "function(t) Dotfiles.sidekick.resize_cli(t, -5) end";
                      mode = "nt";
                      desc = "Sidekick shrink window";
                    };
                    resize_left = {
                      __unkeyed-1 = "<C-S-h>";
                      __unkeyed-2.__raw = ''function(t) Dotfiles.sidekick.resize_toward(t, "left") end'';
                      mode = "nt";
                      desc = "Sidekick resize left";
                    };
                    resize_right = {
                      __unkeyed-1 = "<C-S-l>";
                      __unkeyed-2.__raw = ''function(t) Dotfiles.sidekick.resize_toward(t, "right") end'';
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
            action.__raw = "function() Dotfiles.snacks_picker.ghq_repos() end";
            options.desc = "ghq repos";
          }
          {
            mode = "n";
            key = "<leader><leader>";
            action.__raw = "function() Dotfiles.snacks_picker.smart_files() end";
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
            action.__raw = "function() Dotfiles.snacks.lazygit() end";
            options.desc = "Lazygit";
          }
          {
            mode = "n";
            key = "<leader>gl";
            action.__raw = "function() Dotfiles.snacks.lazygit(true) end";
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
            action.__raw = "function() Dotfiles.float_term.toggle() end";
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
