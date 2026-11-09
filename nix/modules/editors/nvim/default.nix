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
            action.__raw = "function() return jump_completion(1, \"<Tab>\") end";
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
            action.__raw = "function() return jump_completion(-1, \"<S-Tab>\") end";
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
            action.__raw = "function() float_term.grow() end";
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
            action.__raw = "function() float_term.shrink() end";
            options = {
              desc = "Float term: shrink (-5%)";
            };
          }
          {
            mode = "t";
            key = "<A-H>";
            action.__raw = "function() move_float(0, -3) end";
            options = {
              desc = "Float: move left";
            };
          }
          {
            mode = "t";
            key = "<A-J>";
            action.__raw = "function() move_float(3, 0) end";
            options = {
              desc = "Float: move down";
            };
          }
          {
            mode = "t";
            key = "<A-K>";
            action.__raw = "function() move_float(-3, 0) end";
            options = {
              desc = "Float: move up";
            };
          }
          {
            mode = "t";
            key = "<A-L>";
            action.__raw = "function() move_float(0, 3) end";
            options = {
              desc = "Float: move right";
            };
          }
          {
            mode = "n";
            key = "<M-\\>";
            action.__raw = "add_terminal_session";
            options = {
              desc = "New terminal session";
            };
          }
          {
            mode = "t";
            key = "<M-\\>";
            action.__raw = "function() vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(\"<C-\\\\><C-n>\", true, false, true), \"n\", true); vim.schedule(add_terminal_session) end";
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
                  local function emit_osc7(path)
                      if not path or path == "" then
                          return
                      end

                      -- vim.uri_from_fname handles spaces and Windows paths safely.
                      local uri = vim.uri_from_fname(path)
                      vim.api.nvim_ui_send(string.format("\27]7;%s\27\\", uri))
                  end

                  if vim.bo.filetype == "oil" then
                      local ok, oil = pcall(require, "oil")
                      if ok then
                          -- Windows のドライブ root (C:\) など、oil の get_current_dir が
                          -- 内部で `attempt to index local 'drive' (a nil value)` を投げる
                          -- ケースがあるため pcall で吸収し、フォールバックで getcwd() を使う。
                          local got_dir, oil_dir = pcall(oil.get_current_dir)
                          if got_dir and oil_dir and oil_dir ~= "" then
                              emit_osc7(oil_dir)
                              return
                          end
                      end
                  end

                  emit_osc7(vim.fn.getcwd())
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
            event = "WinNew";
            group = "FloatPersist";
            callback.__raw = ''
              function()
                  local win = vim.api.nvim_get_current_win()
                  vim.defer_fn(function()
                      if not vim.api.nvim_win_is_valid(win) then
                          return
                      end
                      local cfg = vim.api.nvim_win_get_config(win)
                      if cfg.relative == "" then
                          return
                      end
                      float_persist.restore(win)
                  end, 80)
              end
            '';
          }
          {
            event = "VimResized";
            group = "FloatTermResize";
            callback.__raw = "float_term.on_resize";
          }
          {
            event = "TermOpen";
            group = "DotfilesTerminal";
            callback.__raw = "terminal_options";
          }
        ];
        userCommands = {
          Term = {
            command.__raw = ''function() vim.cmd("botright 15split | terminal"); vim.cmd("startinsert") end'';
            desc = "Open terminal in bottom split";
          };
          MarpPreview = {
            command.__raw = "marp.start";
            desc = "Start Marp preview server";
          };
          MarpStop = {
            command.__raw = "marp.stop";
            desc = "Stop Marp preview server";
          };
          MarpToggle = {
            command.__raw = "marp.toggle";
            desc = "Toggle Marp preview server";
          };
          MarpStatus = {
            command.__raw = "marp.status";
            desc = "Show Marp preview server status";
          };
        };
        extraConfigVim = ''
          cabbrev <expr> terminal (getcmdtype() == ':' && getcmdpos() <= 9) ? 'Term' : 'terminal'
        '';
        extraConfigLuaPre = lib.mkOrder 650 ''
          local float_persist = (function()
              -- Persist floating window position across sessions.
              -- Keys windows by title (snacks windows) or buftype (plain terminal floats).
              local M = {}

              local path = vim.fn.stdpath("data") .. "/nvim_float_positions.json"

              local function read()
                  local ok, lines = pcall(vim.fn.readfile, path)
                  if not ok or #lines == 0 then
                      return {}
                  end
                  local ok2, t = pcall(vim.json.decode, lines[1])
                  return (ok2 and type(t) == "table") and t or {}
              end

              local function write(t)
                  pcall(vim.fn.writefile, { vim.json.encode(t) }, path)
              end

              local function win_key(win)
                  if not vim.api.nvim_win_is_valid(win) then
                      return nil
                  end
                  local cfg = vim.api.nvim_win_get_config(win)
                  local title = cfg.title
                  if type(title) == "string" and title ~= "" then
                      return title
                  elseif type(title) == "table" and title[1] then
                      local t0 = title[1]
                      local s = type(t0) == "string" and t0 or (type(t0) == "table" and t0[1] or nil)
                      if type(s) == "string" and s ~= "" then
                          return s
                      end
                  end
                  local buf = vim.api.nvim_win_get_buf(win)
                  if vim.bo[buf].buftype == "terminal" then
                      return "terminal"
                  end
                  local ft = vim.bo[buf].filetype
                  return ft ~= "" and ("ft:" .. ft) or nil
              end

              function M.save(win)
                  if not vim.api.nvim_win_is_valid(win) then
                      return
                  end
                  local cfg = vim.api.nvim_win_get_config(win)
                  if cfg.relative == "" then
                      return
                  end
                  local key = win_key(win)
                  if not key then
                      return
                  end
                  local t = read()
                  t[key] = { row = cfg.row, col = cfg.col, width = cfg.width, height = cfg.height }
                  write(t)
              end

              function M.restore(win)
                  if not vim.api.nvim_win_is_valid(win) then
                      return
                  end
                  local cfg = vim.api.nvim_win_get_config(win)
                  if cfg.relative == "" then
                      return
                  end
                  local key = win_key(win)
                  if not key then
                      return
                  end
                  local saved = read()[key]
                  if not saved then
                      return
                  end
                  local patch = { row = saved.row, col = saved.col }
                  if saved.width then
                      patch.width = saved.width
                  end
                  if saved.height then
                      patch.height = saved.height
                  end
                  pcall(vim.api.nvim_win_set_config, win, patch)
              end

              return M
          end)()

          local float_term = (function()
              -- Floating terminal toggle + dynamic resize.
              -- nvim_open_win() で作った current buffer に jobstart({ term = true }) で
              -- terminal を起動する。位置とサイズの管理を float_persist と共有する。
              -- 寸法は Nixvim globals.dotfiles_float_style を参照し、現セッション中の
              -- ratio 上書きはモジュール local state に保持する (toggle hide でも維持される)。
              -- id ごとに buf/win を分けて持つことで、shell / lazygit など複数の float
              -- terminal を独立に toggle できる。ratio は全 id 共通 (ユーザの体感上は
              -- 「float の大きさ」は一つで良い)。
              local style = vim.g.dotfiles_float_style

              local M = {}

              -- Instances keyed by id. ratio は全インスタンスで共有する。
              local instances = {}
              local ratio = nil

              local ratio_path = vim.fn.stdpath("data") .. "/nvim_float_term_ratio.json"

              local function load_ratio()
                  local ok, lines = pcall(vim.fn.readfile, ratio_path)
                  if not ok or #lines == 0 then
                      return
                  end
                  local ok2, saved = pcall(vim.json.decode, lines[1])
                  if ok2 and saved and type(saved.ratio) == "number" then
                      ratio = saved.ratio
                  end
              end

              local function save_ratio()
                  pcall(vim.fn.writefile, { vim.json.encode({ ratio = ratio }) }, ratio_path)
              end

              local function current_ratio()
                  return ratio or style.width
              end

              local function float_config()
                  local r = current_ratio()
                  local width = math.floor(vim.o.columns * r)
                  local height = math.floor(vim.o.lines * r)
                  return {
                      relative = "editor",
                      row = math.floor((vim.o.lines - height) / 2),
                      col = math.floor((vim.o.columns - width) / 2),
                      width = width,
                      height = height,
                      border = style.border,
                  }
              end

              local function get(id)
                  instances[id] = instances[id] or { buf = nil, win = nil }
                  return instances[id]
              end

              local function apply_window_options(win)
                  -- style = "minimal" は環境次第で nvim_open_win の挙動を変えるため、
                  -- ここで明示的に off にする。
                  for name, value in pairs(vim.g.dotfiles_terminal_options) do
                      vim.wo[win][name] = value
                  end
              end

              local function apply_size()
                  for _, inst in pairs(instances) do
                      if inst.win and vim.api.nvim_win_is_valid(inst.win) then
                          pcall(vim.api.nvim_win_set_config, inst.win, float_config())
                      end
                  end
              end

              ---@class config.FloatTerm.ToggleOpts
              ---@field id? string                  instance id (default "shell")
              ---@field cmd? string | string[]      command to run (default shell)
              ---@field cwd? string                 working directory
              ---@field env? table<string, string>  extra env vars (merged with parent env)

              ---@param opts? config.FloatTerm.ToggleOpts
              function M.toggle(opts)
                  opts = opts or {}
                  local id = opts.id or "shell"
                  local cmd = opts.cmd or vim.o.shell
                  local cwd = opts.cwd
                  local env = opts.env
                  local inst = get(id)

                  -- Already open → hide (buf は保持して次回再表示で resume できるように)。
                  if inst.win and vim.api.nvim_win_is_valid(inst.win) then
                      vim.api.nvim_win_hide(inst.win)
                      inst.win = nil
                      return
                  end

                  -- cwd / cmd / env が前回と違う場合は古い buffer を捨てて新規に作り直す。
                  -- 例: repo A で lazygit を開いて hide → repo B に移動して再 toggle、を
                  -- そのまま reuse すると A の lazygit プロセスが見えてしまう。
                  if
                      inst.buf
                      and vim.api.nvim_buf_is_valid(inst.buf)
                      and (not vim.deep_equal(inst.cmd, cmd) or inst.cwd ~= cwd or not vim.deep_equal(inst.env, env))
                  then
                      pcall(vim.api.nvim_buf_delete, inst.buf, { force = true })
                      inst.buf = nil
                  end

                  local reuse = inst.buf and vim.api.nvim_buf_is_valid(inst.buf)
                  if not reuse then
                      inst.buf = vim.api.nvim_create_buf(false, true)
                      inst.cmd = cmd
                      inst.cwd = cwd
                      inst.env = env
                  end

                  local cfg = float_config()
                  inst.win = vim.api.nvim_open_win(inst.buf, true, cfg)
                  apply_window_options(inst.win)

                  if not reuse then
                      -- float が current の状態で jobstart({term=true}) を直接呼ぶ。
                      -- nvim_buf_call を経由すると temporary split が生成され float が壊れる。
                      -- jobstart({term=true}) は termopen() に代わる現行 API。
                      vim.fn.jobstart(cmd, {
                          cwd = cwd,
                          env = env,
                          term = true,
                          on_exit = function()
                              inst.buf = nil
                              inst.cmd = nil
                              inst.cwd = nil
                              inst.env = nil
                              if inst.win and vim.api.nvim_win_is_valid(inst.win) then
                                  pcall(vim.api.nvim_win_close, inst.win, true)
                              end
                              inst.win = nil
                          end,
                      })
                  end

                  vim.cmd("startinsert")
              end

              function M.grow()
                  ratio = math.min(current_ratio() + style.step, style.max_ratio)
                  apply_size()
                  save_ratio()
              end

              function M.shrink()
                  ratio = math.max(current_ratio() - style.step, style.min_ratio)
                  apply_size()
                  save_ratio()
              end

              -- 端末リサイズ時に開いている float terminal を新しい画面寸法に合わせる。
              -- nvim_win_set_config では emulator に古い border が残り続けるため、
              -- window を一度閉じて再オープンすることで完全に消す。
              -- terminal mode で作業中なら resize 後も terminal mode に戻す。
              function M.on_resize()
                  local visible = {}
                  for id, inst in pairs(instances) do
                      if inst.win and vim.api.nvim_win_is_valid(inst.win) then
                          visible[#visible + 1] = id
                      end
                  end
                  if #visible == 0 then
                      return
                  end
                  local was_in_terminal = vim.api.nvim_get_mode().mode == "t"
                  vim.schedule(function()
                      for _, id in ipairs(visible) do
                          local inst = instances[id]
                          if inst and inst.win and vim.api.nvim_win_is_valid(inst.win) then
                              pcall(vim.api.nvim_win_close, inst.win, true)
                              inst.win = nil
                          end
                          if inst and inst.buf and vim.api.nvim_buf_is_valid(inst.buf) then
                              inst.win = vim.api.nvim_open_win(inst.buf, true, float_config())
                              apply_window_options(inst.win)
                          end
                      end
                      if was_in_terminal then
                          vim.cmd("startinsert")
                      end
                  end)
              end

              load_ratio()

              return M
          end)()

          local function terminal_options(args)
              for _, win in ipairs(vim.fn.win_findbuf(args.buf)) do
                  for name, value in pairs(vim.g.dotfiles_terminal_options) do
                      vim.wo[win][name] = value
                  end
              end
          end

          local function move_float(dr, dc)
              local win = vim.api.nvim_get_current_win()
              local cfg = vim.api.nvim_win_get_config(win)
              if cfg.relative == "" then
                  return
              end
              cfg.row = (cfg.row or 0) + dr
              cfg.col = (cfg.col or 0) + dc
              vim.api.nvim_win_set_config(win, cfg)
              float_persist.save(win)
          end

          local function add_terminal_session()
              local term_win = nil
              for _, win in ipairs(vim.api.nvim_list_wins()) do
                  local is_float = vim.api.nvim_win_get_config(win).relative ~= ""
                  if not is_float and vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal" then
                      term_win = win
                      break
                  end
              end
              if term_win then
                  vim.api.nvim_set_current_win(term_win)
                  vim.cmd("vsplit | terminal")
              else
                  vim.cmd("botright 15split | terminal")
              end
              local new_win = vim.api.nvim_get_current_win()
              vim.schedule(function()
                  if vim.api.nvim_win_is_valid(new_win) then
                      terminal_options({ buf = vim.api.nvim_win_get_buf(new_win) })
                  end
              end)
              vim.cmd("startinsert")
          end

          local function jump_completion(direction, fallback)
              if vim.fn.pumvisible() == 1 then
                  return direction == 1 and "<C-n>" or "<C-p>"
              end
              if vim.snippet.active({ direction = direction }) then
                  vim.schedule(function()
                      vim.snippet.jump(direction)
                  end)
                  return ""
              end
              return fallback
          end

          local marp = (function()
              local M = {}

              local state = {
                  job = nil,
                  root = nil,
                  stopping = false,
                  url = "http://localhost:8080/",
              }

              local function current_start_path()
                  local file = vim.api.nvim_buf_get_name(0)
                  if file ~= "" then
                      return vim.fs.dirname(file)
                  end
                  return vim.uv.cwd()
              end

              local function project_root()
                  return vim.fs.root(current_start_path(), { "package.json", ".git" }) or vim.uv.cwd()
              end

              local function has_slide_preview_script(root)
                  local package_json = root .. "/package.json"
                  if vim.fn.filereadable(package_json) == 0 then
                      return false
                  end

                  local ok, parsed = pcall(vim.json.decode, table.concat(vim.fn.readfile(package_json), "\n"))
                  return ok and parsed and parsed.scripts and parsed.scripts["slide:preview"] ~= nil
              end

              local function open_url(url)
                  local _, err = vim.ui.open(url)
                  if err then
                      vim.notify(err, vim.log.levels.ERROR)
                  end
              end

              local function open_when_ready(line)
                  local url = line:match("(https?://localhost:%d+/?)")
                  if not url then
                      return false
                  end
                  state.url = url
                  open_url(url)
                  return true
              end

              function M.start()
                  if state.job and state.job > 0 then
                      open_url(state.url)
                      vim.notify("Marp preview is already running: " .. state.url, vim.log.levels.INFO)
                      return
                  end

                  local root = project_root()
                  if not has_slide_preview_script(root) then
                      vim.notify("No slide:preview script found in " .. root, vim.log.levels.WARN)
                      return
                  end

                  state.root = root
                  state.url = "http://localhost:8080/"
                  local opened = false
                  local function on_output(_, data)
                      for _, line in ipairs(data or {}) do
                          if line ~= "" then
                              opened = open_when_ready(line) or opened
                          end
                      end
                  end

                  state.job = vim.fn.jobstart({ "bun", "run", "slide:preview" }, {
                      cwd = root,
                      stdout_buffered = false,
                      stderr_buffered = false,
                      on_stdout = on_output,
                      on_stderr = on_output,
                      on_exit = function(_, code)
                          local stopping = state.stopping
                          state.job = nil
                          state.stopping = false
                          if code ~= 0 and not stopping then
                              vim.notify("Marp preview exited with code " .. code, vim.log.levels.WARN)
                          end
                      end,
                  })

                  if state.job <= 0 then
                      state.job = nil
                      vim.notify("Failed to start Marp preview", vim.log.levels.ERROR)
                      return
                  end

                  vim.defer_fn(function()
                      if state.job and not opened then
                          open_url(state.url)
                      end
                  end, 1200)
              end

              function M.stop()
                  if not state.job then
                      vim.notify("Marp preview is not running", vim.log.levels.INFO)
                      return
                  end
                  state.stopping = true
                  vim.fn.jobstop(state.job)
              end

              function M.toggle()
                  if state.job then
                      M.stop()
                  else
                      M.start()
                  end
              end

              function M.status()
                  if state.job then
                      vim.notify("Marp preview running: " .. state.url .. " (" .. state.root .. ")", vim.log.levels.INFO)
                  else
                      vim.notify("Marp preview is not running", vim.log.levels.INFO)
                  end
              end

              return M
          end)()
        '';
        assertions = [
          {
            assertion = lib.versionAtLeast config.package.version "0.12";
            message = "This configuration requires Neovim 0.12 or newer.";
          }
        ];
      };
    };
}
