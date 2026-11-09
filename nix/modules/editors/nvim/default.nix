{
  inputs,
  ...
}:
{
  imports = [ inputs.nixvim.homeModules.nixvim ];

  programs.nixvim =
    {
      config,
      lib,
      hmConfig,
      ...
    }:
    {
      config = lib.mkIf config.enable {
        nixpkgs.useGlobalPackages = true;
        # 設定と Lua は package の runtime に含め、XDG 側へ複製しない。
        wrapRc = true;
        impureRtp = false;
        autowrapRuntimeDeps = false;
        withPython3 = false;
        withRuby = false;
        globals = {
          mapleader = " ";
          maplocalleader = " ";
          dotfiles_terminal_options = {
            number = false;
            relativenumber = false;
            signcolumn = "no";
            cursorline = false;
            statuscolumn = "";
          };
          dotfiles_yank_highlight = {
            higroup = "IncSearch";
            timeout = 150;
          };
        };
        globals.dotfiles_float_style = {
          width = 0.85;
          height = 0.85;
          border = "single";
          step = 0.05;
          min_ratio = 0.3;
          max_ratio = 0.98;
        };
        opts = {
          completeopt = [
            "menu"
            "menuone"
            "noselect"
            "popup"
          ];
          fillchars.__raw = ''vim.tbl_extend("force", vim.opt.fillchars:get(), { stl = "─", stlnc = "─" })'';
          # 行番号は絶対値と相対値を表示する。
          number = true;
          relativenumber = true;
          statuscolumn = "%{v:lnum}  %=%{v:relnum?printf('%3d', v:relnum):'   '} ";

          # インデントと矩形選択。
          tabstop = 2;
          softtabstop = 2;
          shiftwidth = 2;
          expandtab = true;
          smartindent = true;
          virtualedit = "block";

          # 検索と置換プレビュー。
          ignorecase = true;
          smartcase = true;
          hlsearch = true;
          incsearch = true;
          inccommand = "split";

          # 表示とマウス操作。
          mouse = "a";
          cmdheight = 0;
          termguicolors = true;
          signcolumn = "yes";
          cursorline = true;
          scrolloff = 8;
          sidescrolloff = 8;
          wrap = true;
          linebreak = true;
          breakindent = true;
          list = true;
          listchars = {
            tab = "» ";
            trail = "·";
            nbsp = "␣";
          };
          laststatus = 0;
          statusline = "─";
          winbar = "";

          # 分割とクリップボード。
          splitbelow = true;
          splitright = true;
          splitkeep = "screen";
          clipboard = "unnamedplus";

          # 保存・再読み込みと応答時間。
          undofile = true;
          undolevels = 10000;
          confirm = true;
          autoread = true;
          updatetime = 250;
          timeoutlen = 300;
          swapfile = false;
          backup = false;
        };

        colorschemes.catppuccin = {
          enable = true;
          settings = {
            flavour = hmConfig.catppuccin.flavor;
            transparent_background = true;
          };
        };

        keymaps = [
          {
            mode = "n";
            key = "<C-h>";
            action = "<C-w>h";
            options.desc = "Go to left window";
          }
          {
            mode = "n";
            key = "<C-j>";
            action = "<C-w>j";
            options.desc = "Go to lower window";
          }
          {
            mode = "n";
            key = "<C-k>";
            action = "<C-w>k";
            options.desc = "Go to upper window";
          }
          {
            mode = "n";
            key = "<C-l>";
            action = "<C-w>l";
            options.desc = "Go to right window";
          }
          {
            mode = "n";
            key = "<C-Up>";
            action = "<cmd>resize +2<cr>";
            options.desc = "Increase window height";
          }
          {
            mode = "n";
            key = "<C-Down>";
            action = "<cmd>resize -2<cr>";
            options.desc = "Decrease window height";
          }
          {
            mode = "n";
            key = "<A-j>";
            action = "<cmd>m .+1<cr>==";
            options.desc = "Move line down";
          }
          {
            mode = "n";
            key = "<A-k>";
            action = "<cmd>m .-2<cr>==";
            options.desc = "Move line up";
          }
          {
            mode = "v";
            key = "<A-j>";
            action = ":m '>+1<cr>gv=gv";
            options.desc = "Move selection down";
          }
          {
            mode = "v";
            key = "<A-k>";
            action = ":m '<-2<cr>gv=gv";
            options.desc = "Move selection up";
          }
          {
            mode = "n";
            key = "<Esc>";
            action = "<cmd>nohlsearch<cr>";
            options.desc = "Clear search highlight";
          }
          {
            mode = [
              "n"
              "i"
              "x"
            ];
            key = "<C-z>";
            action = "<cmd>undo<cr>";
            options.desc = "Undo";
          }
          {
            mode = [
              "n"
              "x"
            ];
            key = "<C-y>";
            action = "<cmd>redo<cr>";
            options.desc = "Redo";
          }
          {
            mode = "v";
            key = "<";
            action = "<gv";
            options.desc = "Indent left";
          }
          {
            mode = "v";
            key = ">";
            action = ">gv";
            options.desc = "Indent right";
          }
          {
            mode = "n";
            key = "<leader>w";
            action = "<cmd>w<cr>";
            options.desc = "Save file";
          }
          {
            mode = "n";
            key = "<C-s>";
            action = "<cmd>w<cr>";
            options.desc = "Save file";
          }
          {
            mode = "n";
            key = "<leader>q";
            action = "<cmd>q<cr>";
            options.desc = "Quit";
          }
          {
            mode = "n";
            key = "<leader>Q";
            action = "<cmd>qa!<cr>";
            options.desc = "Quit all";
          }
          {
            mode = "n";
            key = "<leader>de";
            action.__raw = "vim.diagnostic.open_float";
            options.desc = "Show diagnostic";
          }
          {
            mode = "n";
            key = "<leader>marp";
            action = "<cmd>MarpToggle<cr>";
            options.desc = "Toggle Marp preview";
          }
          {
            mode = "n";
            key = "<leader>\\";
            action = "<cmd>vsplit<cr>";
            options.desc = "Vertical split";
          }
          {
            mode = "n";
            key = "<leader>-";
            action = "<cmd>split<cr>";
            options.desc = "Horizontal split";
          }
          {
            mode = "n";
            key = "<leader>x";
            action = "<cmd>q<cr>";
            options.desc = "Close window";
          }
          {
            mode = "n";
            key = "<leader>h";
            action = "<cmd>bprevious<cr>";
            options.desc = "Prev buffer";
          }
          {
            mode = "n";
            key = "<leader>l";
            action = "<cmd>bnext<cr>";
            options.desc = "Next buffer";
          }
          {
            mode = "t";
            key = "<C-h>";
            action = "<C-\\><C-n><C-w>h";
            options.desc = "Go to left window";
          }
          {
            mode = "t";
            key = "<C-j>";
            action = "<C-\\><C-n><C-w>j";
            options.desc = "Go to lower window";
          }
          {
            mode = "t";
            key = "<C-k>";
            action = "<C-\\><C-n><C-w>k";
            options.desc = "Go to upper window";
          }
          {
            mode = "t";
            key = "<C-l>";
            action = "<C-\\><C-n><C-w>l";
            options.desc = "Go to right window";
          }
          {
            mode = "t";
            key = "<C-q>";
            action = "<C-\\><C-n>";
            options.desc = "Leave terminal mode";
          }
          {
            mode = "n";
            key = "<C-w>w";
            action = "<C-w>w";
            options.desc = "Go to next window";
          }
          {
            mode = "n";
            key = "<C-Left>";
            action = "<cmd>vertical resize -2<cr>";
            options.desc = "Decrease window width";
          }
          {
            mode = "n";
            key = "<C-Right>";
            action = "<cmd>vertical resize +2<cr>";
            options.desc = "Increase window width";
          }
          {
            mode = "n";
            key = "<S-h>";
            action = "<cmd>bprevious<cr>";
            options.desc = "Prev buffer";
          }
          {
            mode = "n";
            key = "<S-l>";
            action = "<cmd>bnext<cr>";
            options.desc = "Next buffer";
          }
          {
            mode = "n";
            key = "<leader>bd";
            action = "<cmd>bdelete<cr>";
            options.desc = "Delete buffer";
          }
          {
            mode = "i";
            key = "<C-Space>";
            action.__raw = "vim.lsp.completion.get";
            options = {
              desc = "LSP completion";
            };
          }
          {
            mode = "i";
            key = "<CR>";
            action.__raw = "Dotfiles.completion.enter";
            options = {
              desc = "Accept selected completion or newline";
              expr = true;
            };
          }
          {
            mode = [
              "i"
              "s"
            ];
            key = "<Tab>";
            action.__raw = "function() return Dotfiles.completion.jump(1, \"<Tab>\") end";
            options = {
              desc = "Completion or snippet navigation";
              expr = true;
            };
          }
          {
            mode = [
              "i"
              "s"
            ];
            key = "<S-Tab>";
            action.__raw = "function() return Dotfiles.completion.jump(-1, \"<S-Tab>\") end";
            options = {
              desc = "Completion or snippet navigation";
              expr = true;
            };
          }
          {
            mode = [
              "n"
              "t"
            ];
            key = "<M-+>";
            action.__raw = "function() Dotfiles.float_term.grow() end";
            options = {
              desc = "Float term: grow (+5%)";
            };
          }
          {
            mode = [
              "n"
              "t"
            ];
            key = "<M-_>";
            action.__raw = "function() Dotfiles.float_term.shrink() end";
            options = {
              desc = "Float term: shrink (-5%)";
            };
          }
          {
            mode = "t";
            key = "<A-H>";
            action.__raw = "function() Dotfiles.keymaps.move_float(0, -3) end";
            options = {
              desc = "Float: move left";
            };
          }
          {
            mode = "t";
            key = "<A-J>";
            action.__raw = "function() Dotfiles.keymaps.move_float(3, 0) end";
            options = {
              desc = "Float: move down";
            };
          }
          {
            mode = "t";
            key = "<A-K>";
            action.__raw = "function() Dotfiles.keymaps.move_float(-3, 0) end";
            options = {
              desc = "Float: move up";
            };
          }
          {
            mode = "t";
            key = "<A-L>";
            action.__raw = "function() Dotfiles.keymaps.move_float(0, 3) end";
            options = {
              desc = "Float: move right";
            };
          }
          {
            mode = "n";
            key = "<M-\\>";
            action.__raw = "Dotfiles.keymaps.add_terminal_session";
            options = {
              desc = "New terminal session";
            };
          }
          {
            mode = "t";
            key = "<M-\\>";
            action.__raw = "function() vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(\"<C-\\\\><C-n>\", true, false, true), \"n\", true); vim.schedule(Dotfiles.keymaps.add_terminal_session) end";
            options = {
              desc = "New terminal session";
            };
          }
        ];
        autoGroups = {
          DotfilesEditing.clear = true;
          DotfilesOsc7.clear = true;
          FloatPersist.clear = true;
          FloatTermResize.clear = true;
          DotfilesTerminal.clear = true;
        };
        autoCmd = [
          {
            event = "TextYankPost";
            group = "DotfilesEditing";
            callback.__raw = "function() vim.hl.on_yank(vim.g.dotfiles_yank_highlight) end";
          }
          {
            event = "BufReadPost";
            group = "DotfilesEditing";
            callback.__raw = "Dotfiles.autocmds.restore_cursor";
          }
          {
            event = [
              "FocusGained"
              "TermClose"
            ];
            group = "DotfilesEditing";
            callback.__raw = "Dotfiles.autocmds.checktime";
          }
          {
            event = [
              "VimEnter"
              "DirChanged"
              "BufEnter"
            ];
            group = "DotfilesOsc7";
            callback.__raw = "Dotfiles.osc7.sync_cwd_to_terminal";
          }
          {
            event = "VimLeave";
            group = "DotfilesTerminal";
            callback.__raw = "Dotfiles.osc7.restore_terminal";
          }
          {
            event = "WinNew";
            group = "FloatPersist";
            callback.__raw = "Dotfiles.float_persist.on_win_new";
          }
          {
            event = "VimResized";
            group = "FloatTermResize";
            callback.__raw = "Dotfiles.float_term.on_resize";
          }
          {
            event = "TermOpen";
            group = "DotfilesTerminal";
            callback.__raw = "Dotfiles.keymaps.terminal_options";
          }
        ];
        userCommands = {
          Term = {
            command.__raw = ''function() vim.cmd("botright 15split | terminal"); vim.cmd("startinsert") end'';
            desc = "Open terminal in bottom split";
          };
          MarpPreview = {
            command.__raw = "Dotfiles.marp.start";
            desc = "Start Marp preview server";
          };
          MarpStop = {
            command.__raw = "Dotfiles.marp.stop";
            desc = "Stop Marp preview server";
          };
          MarpToggle = {
            command.__raw = "Dotfiles.marp.toggle";
            desc = "Toggle Marp preview server";
          };
          MarpStatus = {
            command.__raw = "Dotfiles.marp.status";
            desc = "Show Marp preview server status";
          };
        };
        extraConfigVim = ''
          cabbrev <expr> terminal (getcmdtype() == ':' && getcmdpos() <= 9) ? 'Term' : 'terminal'
        '';
        extraConfigLuaPre = lib.mkOrder 650 (import ./callbacks.nix);
        assertions = [
          {
            assertion = lib.versionAtLeast config.package.version "0.12";
            message = "This configuration requires Neovim 0.12 or newer.";
          }
        ];
      };
    };
}
