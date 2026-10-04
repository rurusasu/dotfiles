local M = {}

-- Executable names are explicit: upstream cmd may be a function (e.g. ts_ls).
M.servers = {
    nixd = "nixd",
    gopls = "gopls",
    rust_analyzer = "rust-analyzer",
    oxlint = "oxlint",
    yamlls = "yaml-language-server",
    taplo = "taplo",
    bashls = "bash-language-server",
    lua_ls = "lua-language-server",
    tsc = "tsc",
    ts_ls = "typescript-language-server",
    marksman = "marksman",
    ruff = "ruff",
    ty = "ty",
}

local formatters = { python = "ruff", rust = "rust_analyzer" }
local guarded = {}

-- ファイル種別に合う整形対応 LSP を一つだけ選び、二重整形を防ぐ。
local function format_buffer(buf, async)
    if vim.bo[buf].buftype ~= "" or not vim.bo[buf].modifiable then
        return
    end
    local clients = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/formatting" })
    table.sort(clients, function(a, b)
        return a.id < b.id
    end)
    local preferred = formatters[vim.bo[buf].filetype]
    for _, client in ipairs(clients) do
        if not preferred or client.name == preferred then
            vim.lsp.buf.format({ bufnr = buf, id = client.id, async = async, timeout_ms = 3000 })
            return
        end
    end
end

local function guard_function_command(name, cfg, executable)
    if guarded[name] or name == "tsc" or name == "ts_ls" then
        return -- TypeScript already selects an executable per root.
    end
    local upstream_root = cfg.root_dir
    vim.lsp.config(name, {
        root_dir = function(buf, on_dir)
            local function available(root)
                if
                    vim.fn.executable(executable) == 1
                    or (root and vim.fn.executable(vim.fs.joinpath(root, "node_modules", ".bin", executable)) == 1)
                then
                    on_dir(root)
                end
            end
            if type(upstream_root) == "function" then
                upstream_root(buf, available)
            else
                -- Mirror native root_markers resolution, including rootless
                -- buffers. Do not invent a cwd workspace or override Deno rules.
                available(upstream_root or vim.fs.root(buf, cfg.root_markers or {}))
            end
        end,
    })
    guarded[name] = true
end

local function on_attach(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if not client then
        return
    end
    local buf = args.buf
    if client.name == "ruff" then
        client.server_capabilities.hoverProvider = false -- ty owns Python hover/type information.
    end
    if client:supports_method("textDocument/completion", buf) then
        vim.lsp.completion.enable(true, client.id, buf, { autotrigger = true })
    end
    local function map(keys, rhs, desc)
        vim.keymap.set("n", keys, rhs, { buffer = buf, desc = desc })
    end
    map("gd", function()
        if #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/definition" }) > 0 then
            vim.lsp.buf.definition()
        else
            require("snacks").picker.grep_word()
        end
    end, "Go to definition")
    -- Keep grr/grn/gra/gri/grt and K provided by Neovim.
    map("<leader>rn", vim.lsp.buf.rename, "Rename")
    map("<leader>ca", vim.lsp.buf.code_action, "Code action")
    map("<leader>f", function()
        format_buffer(buf, true)
    end, "Format")
end

local function start_enabled_for_buffer(name, buf)
    local cfg = vim.lsp.config[name]
    local filetype = vim.bo[buf].filetype
    if not cfg or type(cfg.filetypes) == "table" and not vim.tbl_contains(cfg.filetypes, filetype) then
        return
    end

    local config = vim.deepcopy(cfg)
    local function start(root_dir)
        config.root_dir = root_dir
        vim.schedule(function()
            if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == filetype then
                vim.lsp.start(config, {
                    bufnr = buf,
                    reuse_client = config.reuse_client,
                    _root_markers = config.root_markers,
                })
            end
        end)
    end

    if type(config.root_dir) == "function" then
        config.root_dir(buf, start)
    else
        start(config.root_dir)
    end
end

function M.setup()
    -- 個人環境の補完・診断設定は追加せず、整形に必要な設定だけを指定する。
    vim.lsp.config("nixd", {
        settings = { nixd = { formatting = { command = { "nixfmt" } } } },
    })
    vim.lsp.config("yamlls", {
        settings = { yaml = { format = { enable = true } } },
    })
    vim.lsp.config("gopls", {
        settings = { gopls = { gofumpt = true } },
    })
    require("config.typescript").setup()
    local group = vim.api.nvim_create_augroup("DotfilesLsp", { clear = true })
    vim.api.nvim_create_autocmd("LspAttach", { group = group, callback = on_attach })
    vim.api.nvim_create_autocmd("BufWritePre", {
        group = group,
        -- 拡張子から判定された filetype の LSP が整形対応なら、保存前に実行する。
        -- 同期実行で、整形後の内容をディスクへ保存する。
        callback = function(args)
            format_buffer(args.buf, false)
        end,
    })
    local function enable_available()
        local newly_enabled = {}
        for name, executable in pairs(M.servers) do
            local cfg = vim.lsp.config[name]
            local available = vim.fn.executable(executable) == 1
            if cfg and type(cfg.cmd) == "function" then
                -- Function commands resolve their binaries per project, including
                -- projects opened after this plugin's first BufReadPre event.
                available = true
                guard_function_command(name, cfg, executable)
            end
            if cfg and cfg.cmd and available and not vim.lsp.is_enabled(name) then
                vim.lsp.enable(name)
                newly_enabled[#newly_enabled + 1] = name
            end
        end
        -- vim.lsp.enable() cannot replay the FileType event currently being
        -- processed. Start newly available servers for this buffer explicitly.
        local buf = vim.api.nvim_get_current_buf()
        for _, name in ipairs(newly_enabled) do
            start_enabled_for_buffer(name, buf)
        end
    end
    enable_available()
    -- Retry static commands too when PATH changes (e.g. entering a dev shell).
    vim.api.nvim_create_autocmd("FileType", { group = group, callback = enable_available })
end

return M
