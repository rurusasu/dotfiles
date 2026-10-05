---@param ctx snacks.picker.preview.ctx
local function preview_file(ctx)
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
    -- 元の項目を維持し、画像プレビューには PNG のパスとキャッシュを渡す。
    return preview.image(vim.tbl_extend("force", ctx, {
        item = vim.tbl_extend("force", ctx.item, { file = tmp, _path = tmp }),
    }))
end

require("snacks").setup({
    lazygit = { enabled = true },
    terminal = { enabled = true },
    image = {
        enabled = true,
        force = false, -- Let Snacks detect whether the terminal supports images.
        convert = { notify = true },
        -- PDF は picker.preview で Poppler を使うため、画像変換の対象から除外する。
        formats = {
            "png",
            "jpg",
            "jpeg",
            "gif",
            "bmp",
            "webp",
            "tiff",
            "heic",
            "avif",
            "mp4",
            "mov",
            "avi",
            "mkv",
            "webm",
            "icns",
        },
    },
    picker = {
        enabled = true,
        preview = preview_file,
        -- multi のソース別 dispatch を保ち、通常のファイルプレビューだけ置き換える。
        config = function(opts)
            if not opts.multi or opts.preview ~= preview_file then
                return
            end
            opts.preview = nil
            for i, source in ipairs(opts.multi) do
                source = type(source) == "string" and { source = source } or source
                local preset = opts.sources[source.source] or {}
                local source_preview = source.preview or preset.preview
                if not source_preview or source_preview == "file" then
                    opts.multi[i] = vim.tbl_extend("force", source, { preview = preview_file })
                end
            end
        end,
        -- snacks picker から Alt+a で選択中の項目を sidekick の
        -- 現在の AI CLI セッションに送る (ファイルパス / grep ヒット /
        -- 複数選択 / 位置情報まで自動付与される)。
        actions = {
            sidekick_send = function(...)
                return require("sidekick.cli.picker.snacks").send(...)
            end,
        },
        win = {
            input = {
                keys = {
                    ["<a-a>"] = {
                        "sidekick_send",
                        mode = { "n", "i" },
                    },
                },
            },
        },
    },
})

-- 公式例の keys は lazy.nvim 用なので、native package では末尾で登録する。
local keys = {
    {
        "<leader>ff",
        function()
            Snacks.picker.files()
        end,
        desc = "Find files",
    },

    {
        "<leader>fg",
        function()
            Snacks.picker.grep()
        end,
        desc = "Live grep",
    },

    {
        "<leader>fb",
        function()
            Snacks.picker.buffers()
        end,
        desc = "Buffers",
    },

    {
        "<leader>fq",
        function()
            if vim.fn.executable("ghq") == 0 then
                vim.notify("ghq not found", vim.log.levels.WARN)
                return
            end
            Snacks.picker.pick("proc", {
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
        end,
        desc = "ghq repos",
    },

    {
        "<leader><leader>",
        function()
            local picker = require("snacks").picker
            local root = require("snacks.git").get_root()
            local sources = require("snacks.picker.config.sources")

            local files = root == nil and sources.files
                or vim.tbl_deep_extend("force", sources.git_files, {
                    untracked = true,
                    cwd = vim.uv.cwd(),
                })

            picker({
                multi = { "buffers", "recent", files },
                format = "file",
                matcher = { frecency = true, sort_empty = true },
                filter = { cwd = true },
                transform = "unique_file",
            })
        end,
        desc = "Find files (smart)",
    },

    {
        "<leader>gg",
        function()
            local root = Snacks.git.get_root()
            if not root then
                vim.notify("lazygit: not in a git repository", vim.log.levels.WARN)
                return
            end
            if vim.fn.has("win32") == 1 then
                -- Preserve the Windows float workaround until verified
                -- in a real terminal. Empty NVIM prevents remote startup.
                require("config.float_term").toggle({
                    id = "lazygit",
                    cmd = { "lazygit" },
                    cwd = root,
                    env = { NVIM = "" },
                })
            else
                _G.__snacks_last_lg = Snacks.lazygit.open({ cwd = root })
                _G._SNACKS_LG_CLOSE = function()
                    local lg = _G.__snacks_last_lg
                    if lg and lg.close then
                        pcall(lg.close, lg)
                    end
                    _G.__snacks_last_lg = nil
                end
            end
        end,
        desc = "Lazygit",
    },

    {
        "<leader>gl",
        function()
            local root = Snacks.git.get_root()
            if not root then
                return
            end
            if vim.fn.has("win32") == 1 then
                require("config.float_term").toggle({
                    id = "lazygit-log",
                    cmd = { "lazygit", "log" },
                    cwd = root,
                    env = { NVIM = "" },
                })
            else
                Snacks.lazygit.log({ cwd = root })
            end
        end,
        desc = "Git log",
    },

    {
        "<leader>gf",
        function()
            Snacks.lazygit.log_file()
        end,
        desc = "Git log (file)",
    },

    {
        "<leader>tt",
        function()
            Snacks.terminal.toggle(nil, {
                win = { position = "bottom", height = 0.3 },
            })
        end,
        mode = { "n", "t" },
        desc = "Toggle bottom terminal",
    },

    {
        "<leader>tf",
        function()
            -- Keep the custom float's persisted geometry and resize handling.
            require("config.float_term").toggle()
        end,
        mode = { "n", "t" },
        desc = "Toggle floating terminal",
    },
}

for _, key in ipairs(keys) do
    vim.keymap.set(key.mode or "n", key[1], key[2], { desc = key.desc })
end
