''
  _G.Dotfiles = {}

  do
    local M = {}

    function M.restore_cursor(args)
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

    function M.checktime()
        if vim.fn.getcmdwintype() == "" and vim.fn.mode():sub(1, 1) ~= "c" then
            vim.cmd.checktime()
        end
    end

    Dotfiles.autocmds = M
  end

  do
    local M = {}

    function M.enter()
        if vim.fn.pumvisible() == 1 then
            return vim.fn.complete_info({ "selected" }).selected >= 0 and "<C-y>" or "<C-e><CR>"
        end
        return "<CR>"
    end

    function M.jump(direction, fallback)
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

    Dotfiles.completion = M
  end

  do
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

    function M.on_win_new()
        local win = vim.api.nvim_get_current_win()
        vim.defer_fn(function()
            if not vim.api.nvim_win_is_valid(win) then
                return
            end
            local cfg = vim.api.nvim_win_get_config(win)
            if cfg.relative == "" then
                return
            end
            M.restore(win)
        end, 80)
    end

    Dotfiles.float_persist = M
  end

  do
    -- Floating terminal toggle + dynamic resize.
    -- nvim_open_win() で作った current buffer に jobstart({ term = true }) で
    -- terminal を起動する。位置とサイズの管理を config.float_persist と共有する。
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

    local function default_shell()
        return vim.o.shell
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
        local cmd = opts.cmd or default_shell()
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

    function M.reset()
        ratio = nil
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

    Dotfiles.float_term = M
  end

  do
    Dotfiles.highlights = function()
        for name, style in pairs(vim.g.dotfiles_highlights or {}) do
            vim.api.nvim_set_hl(0, name, style)
        end
    end
  end

  do
    local M = {}
    local devicons = require("nvim-web-devicons")

    function M.render(props)
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

    Dotfiles.incline = M
  end

  do
    local M = {}

    function M.move_float(dr, dc)
        local win = vim.api.nvim_get_current_win()
        local cfg = vim.api.nvim_win_get_config(win)
        if cfg.relative == "" then
            return
        end
        cfg.row = (cfg.row or 0) + dr
        cfg.col = (cfg.col or 0) + dc
        vim.api.nvim_win_set_config(win, cfg)
        Dotfiles.float_persist.save(win)
    end

    function M.add_terminal_session()
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
                M.terminal_options({ buf = vim.api.nvim_win_get_buf(new_win) })
            end
        end)
        vim.cmd("startinsert")
    end

    function M.terminal_options(args)
        for _, win in ipairs(vim.fn.win_findbuf(args.buf)) do
            for name, value in pairs(vim.g.dotfiles_terminal_options) do
                vim.wo[win][name] = value
            end
        end
    end

    Dotfiles.keymaps = M
  end

  do
    local M = {}

    function M.format_buffer(buf, async)
        if vim.bo[buf].buftype ~= "" or not vim.bo[buf].modifiable then
            return
        end
        local clients = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/formatting" })
        table.sort(clients, function(a, b)
            return a.id < b.id
        end)
        local preferred = (vim.g.dotfiles_formatters or {})[vim.bo[buf].filetype]
        for _, client in ipairs(clients) do
            if not preferred or client.name == preferred then
                vim.lsp.buf.format({ bufnr = buf, id = client.id, async = async, timeout_ms = 3000 })
                return
            end
        end
    end

    Dotfiles.lsp = M
  end

  do
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

    Dotfiles.marp = M
  end

  do
    local M = {}

    local function emit_osc7(path)
        if not path or path == "" then
            return
        end

        -- vim.uri_from_fname handles spaces and Windows paths safely.
        local uri = vim.uri_from_fname(path)
        vim.api.nvim_ui_send(string.format("\27]7;%s\27\\", uri))
    end

    function M.sync_cwd_to_terminal()
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

    function M.restore_terminal()
        for _, ui in ipairs(vim.api.nvim_list_uis()) do
            if ui.stdout_tty then
                vim.api.nvim_ui_send("\027[?1049l\027[H\027[2J")
                break
            end
        end
    end

    Dotfiles.osc7 = M
  end

  do
    local M = {}

    function M.resize_cli(terminal, delta)
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

    function M.resize_toward(terminal, direction)
        local layout = terminal.opts and terminal.opts.layout or "right"
        if layout == "top" or layout == "bottom" then
            return
        end

        local delta = direction == "left" and 5 or -5
        if layout == "left" then
            delta = -delta
        end
        M.resize_cli(terminal, delta)
    end

    function M.configure_terminal(terminal)
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

    Dotfiles.sidekick = M
  end

  do
    local M = {}
    local Snacks = require("snacks")

    function M.lazygit(log)
        local root = Snacks.git.get_root()
        if not root then
            if not log then
                vim.notify("lazygit: not in a git repository", vim.log.levels.WARN)
            end
            return
        end
        if vim.fn.has("win32") == 1 then
            Dotfiles.float_term.toggle({
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

    function M.terminal_on_buf(terminal)
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

    Dotfiles.snacks = M
  end

  do
    local Snacks = require("snacks")
    local M = {}

    ---@param ctx snacks.picker.preview.ctx
    function M.preview_file(ctx)
        local preview = require("snacks.picker.preview")
        local file = Snacks.picker.util.path(ctx.item) or (ctx.item and ctx.item.path)
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

    -- Preserve dedicated previews in mixed-source pickers, such as Git history.
    function M.configure_previews(opts)
        if not opts.multi or opts.preview ~= M.preview_file then
            return
        end
        opts.preview = nil
        for i, source in ipairs(opts.multi) do
            source = type(source) == "string" and { source = source } or source
            local preset = opts.sources[source.source] or {}
            local preview = source.preview or preset.preview
            if not preview or preview == "file" then
                opts.multi[i] = vim.tbl_extend("force", source, { preview = M.preview_file })
            end
        end
    end

    function M.ghq_repos()
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

    function M.smart_files()
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

    Dotfiles.snacks_picker = M
  end
''
