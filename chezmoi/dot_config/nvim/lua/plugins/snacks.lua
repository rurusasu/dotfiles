return {
    -- UI utilities + lazygit float
    {
        "folke/snacks.nvim",
        lazy = false,
        priority = 1000,
        keys = {
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
                        -- Windows: snacks.terminal の float が split に化けるため
                        -- 自前 float_term で開く。NVIM を空にして nvim-remote 起動を抑止。
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
                    -- snacks.terminal の position = "float" が bottom に化ける問題
                    -- を避けるため、純粋 nvim API で実装した自前 float terminal を使う。
                    require("config.float_term").toggle()
                end,
                mode = { "n", "t" },
                desc = "Toggle floating terminal",
            },
        },
        opts = {
            lazygit = { enabled = true },
            terminal = { enabled = true },
            image = {
                enabled = true,
                force = true,
                convert = { notify = true },
                -- "pdf" を除外: picker では monkey-patch が pdftoppm で処理するため
                -- snacks 自身の magick/Ghostscript パイプラインが走らないようにする
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
        },
        init = function()
            -- PDF: pdftoppm で先頭ページを PNG に変換して snacks image で表示。
            -- snacks.picker.util.path() は item._path をキャッシュするため、
            -- patched item に _path を明示セットしないと元の PDF パスが渡る。
            -- VeryLazy 後に snacks.picker.preview が確実にロードされてからパッチ。
            vim.api.nvim_create_autocmd("User", {
                pattern = "VeryLazy",
                once = true,
                callback = function()
                    local ok, preview = pcall(require, "snacks.picker.preview")
                    if not ok or not preview.file then
                        return
                    end
                    local orig_file = preview.file
                    preview.file = function(ctx)
                        local file = ctx.item and (ctx.item.file or ctx.item.path or "")
                        if file:match("%.pdf$") then
                            if vim.fn.executable("pdftoppm") == 0 then
                                vim.notify(
                                    "PDF preview requires poppler (pdftoppm). Install via: winget install oschwartz10612.Poppler",
                                    vim.log.levels.WARN
                                )
                                return false
                            end
                            local tmp = vim.fn.tempname()
                            vim.fn.system({ "pdftoppm", "-png", "-r", "150", "-singlefile", file, tmp })
                            tmp = tmp .. ".png"
                            -- _path をリセットしないと元の PDF パスのキャッシュが残る
                            local patched = vim.tbl_deep_extend("force", ctx, {
                                item = vim.tbl_extend("force", ctx.item, { file = tmp, _path = tmp }),
                            })
                            return preview.image and preview.image(patched) or false
                        end
                        return orig_file(ctx)
                    end
                end,
            })
        end,
    },
}
