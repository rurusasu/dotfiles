{
  inputs,
  platform,
  ...
}:
{
  imports = [
    inputs.nixvim.homeModules.nixvim
    ./lsp
    ./plugins
  ];

  programs.nixvim =
    {
      config,
      lib,
      ...
    }:
    {
      config = lib.mkMerge [
        { enable = true; }
        (lib.mkIf config.enable {
          nixpkgs.useGlobalPackages = true;
          globals.clipboard = lib.mkIf (platform == "wsl") {
            name = "win32yank";
            copy = {
              "+" = "win32yank.exe -i --crlf";
              "*" = "win32yank.exe -i --crlf";
            };
            paste = {
              "+" = "win32yank.exe -o --lf";
              "*" = "win32yank.exe -o --lf";
            };
            cache_enabled = 0;
          };

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
              action.__raw = ''
                function()
                    if vim.fn.pumvisible() == 1 then
                        return vim.fn.complete_info({ "selected" }).selected >= 0 and "<C-y>" or "<C-e><CR>"
                    end
                    return "<CR>"
                end
              '';
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
              action.__raw = ''
                function()
                    if vim.fn.pumvisible() == 1 then
                        return "<C-n>"
                    end
                    if vim.snippet.active({ direction = 1 }) then
                        vim.schedule(function() vim.snippet.jump(1) end)
                        return ""
                    end
                    return "<Tab>"
                end
              '';
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
              action.__raw = ''
                function()
                    if vim.fn.pumvisible() == 1 then
                        return "<C-p>"
                    end
                    if vim.snippet.active({ direction = -1 }) then
                        vim.schedule(function() vim.snippet.jump(-1) end)
                        return ""
                    end
                    return "<S-Tab>"
                end
              '';
              options = {
                desc = "Completion or snippet navigation";
                expr = true;
              };
            }
            {
              mode = "n";
              key = "<M-\\>";
              action = "<cmd>TermNew<cr>";
              options = {
                desc = "New terminal session";
              };
            }
            {
              mode = "t";
              key = "<M-\\>";
              action = "<C-\\><C-n><cmd>TermNew<cr>";
              options = {
                desc = "New terminal session";
              };
            }
          ];
          autoGroups = {
            DotfilesEditing.clear = true;
            DotfilesOsc7.clear = true;
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
              callback.__raw = ''
                function(args)
                    local buf = args.buf
                    if vim.bo[buf].buftype ~= "" or vim.bo[buf].filetype == "gitcommit" or vim.bo[buf].filetype == "gitrebase" then
                        return
                    end
                    local win = vim.api.nvim_get_current_win()
                    if vim.api.nvim_win_get_buf(win) ~= buf then
                        return
                    end
                    local cursor = vim.api.nvim_win_get_cursor(win)
                    if cursor[1] ~= 1 or cursor[2] ~= 0 then
                        return
                    end
                    local mark = vim.api.nvim_buf_get_mark(buf, '"')
                    if mark[1] == 0 or mark[1] > vim.api.nvim_buf_line_count(buf) then
                        return
                    end
                    local line = vim.api.nvim_buf_get_lines(buf, mark[1] - 1, mark[1], false)[1]
                    vim.api.nvim_win_set_cursor(win, { mark[1], math.min(mark[2], #line) })
                    vim.cmd.normal({ "zv", bang = true })
                end
              '';
            }
            {
              event = [
                "FocusGained"
                "TermClose"
              ];
              group = "DotfilesEditing";
              callback.__raw = ''
                function()
                    if vim.fn.getcmdwintype() == "" and vim.fn.mode():sub(1, 1) ~= "c" then
                        vim.cmd.checktime()
                    end
                end
              '';
            }
            {
              event = [
                "VimEnter"
                "DirChanged"
                "BufEnter"
              ];
              group = "DotfilesOsc7";
              callback.__raw = ''
                function()
                    if vim.bo.buftype ~= "" then
                        return
                    end
                    local uri = vim.uri_from_fname(vim.fn.getcwd())
                    vim.api.nvim_ui_send(string.format("\27]7;%s\27\\", uri))
                end
              '';
            }
            {
              event = "VimLeave";
              group = "DotfilesTerminal";
              callback.__raw = ''
                function()
                    for _, ui in ipairs(vim.api.nvim_list_uis()) do
                        if ui.stdout_tty then
                            vim.api.nvim_ui_send("\027[?1049l\027[H\027[2J")
                            break
                        end
                    end
                end
              '';
            }
            {
              event = "TermOpen";
              group = "DotfilesTerminal";
              callback.__raw = ''
                function(args)
                    for _, win in ipairs(vim.fn.win_findbuf(args.buf)) do
                        for name, value in pairs(vim.g.dotfiles_terminal_options) do
                            vim.wo[win][name] = value
                        end
                    end
                end
              '';
            }
          ];
          userCommands = {
            Term = {
              command.__raw = ''function() vim.cmd("botright 15split | terminal"); vim.cmd("startinsert") end'';
              desc = "Open terminal in bottom split";
            };
            TermNew = {
              command.__raw = ''
                function()
                    for _, win in ipairs(vim.api.nvim_list_wins()) do
                        if vim.api.nvim_win_get_config(win).relative == ""
                            and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal" then
                            vim.api.nvim_set_current_win(win)
                            vim.cmd("vsplit | terminal | startinsert")
                            return
                        end
                    end
                    vim.cmd("Term")
                end
              '';
              desc = "Add a split terminal session";
            };
          };
          extraConfigVim = ''
            cabbrev <expr> terminal (getcmdtype() == ':' && getcmdpos() <= 9) ? 'Term' : 'terminal'
          '';
        })
      ];
    };
}
