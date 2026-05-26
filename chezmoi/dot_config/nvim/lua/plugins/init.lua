-- Plugin specifications for lazy.nvim

return {
    -- Colorscheme
    {
        "rebelot/kanagawa.nvim",
        lazy = false,
        priority = 1000,
        config = function()
            vim.cmd.colorscheme("kanagawa-dragon")
        end,
    },

    -- File explorer
    -- Eager-load so oil hijacks netrw at startup; otherwise `nvim <dir>`
    -- (e.g. `nvim .` from tmux/`dcnvim`) is handled by built-in netrw
    -- before oil's setup runs.
    {
        "stevearc/oil.nvim",
        lazy = false,
        keys = { { "-", "<cmd>Oil<cr>", desc = "Open parent directory" } },
        opts = {
            default_file_explorer = true,
            view_options = { show_hidden = true },
            win_options = {
                conceallevel = 3,
                concealcursor = "nvic",
            },
            watch_for_changes = true,
            keymaps = {
                ["\\"] = { "actions.select", opts = { vertical = true }, desc = "Open vsplit" },
                ["|"] = { "actions.select", opts = { vertical = true }, desc = "Open vsplit" },
                ["s"] = { "actions.select", opts = { horizontal = true }, desc = "Open hsplit" },
                ["t"] = { "actions.select", opts = { tab = true }, desc = "Open in new tab" },
                ["<C-h>"] = false,
                ["<C-l>"] = false,
            },
        },
        config = function(_, opts)
            require("oil").setup(opts)
            vim.api.nvim_create_autocmd("FileType", {
                pattern = "oil",
                callback = function()
                    local cmp = package.loaded["cmp"]
                    if cmp then
                        cmp.setup.buffer({ enabled = false })
                    end
                end,
            })
            -- wmic was removed in Windows 11; patch drive listing to use PowerShell.
            if vim.fn.has("win32") == 1 and vim.fn.executable("wmic") == 0 then
                local files = require("oil.adapters.files")
                local cache = require("oil.cache")
                local util = require("oil.util")
                local orig = files.list
                files.list = function(url, column_defs, cb)
                    local _, path = util.parse_url(url)
                    if path ~= "/" then
                        return orig(url, column_defs, cb)
                    end
                    local stdout = ""
                    local jid = vim.fn.jobstart({
                        "powershell.exe",
                        "-NoProfile",
                        "-Command",
                        "Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Name + ':' }",
                    }, {
                        stdout_buffered = true,
                        on_stdout = function(_, data)
                            stdout = table.concat(data, "\n")
                        end,
                        on_exit = function(_, code)
                            if code ~= 0 then
                                return cb("Error listing windows devices")
                            end
                            local entries = {}
                            for _, line in ipairs(vim.split(stdout, "\n", { trimempty = true })) do
                                local drive = line:match("^(%a+):?%s*$")
                                if drive then
                                    table.insert(entries, cache.create_entry(url, drive, "directory"))
                                end
                            end
                            cb(nil, entries)
                        end,
                    })
                    if jid <= 0 then
                        cb("Could not list windows devices")
                    end
                end
            end
        end,
    },

    -- Fuzzy finder
    {
        "nvim-telescope/telescope.nvim",
        cmd = "Telescope",
        keys = {
            { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
            { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live grep" },
            { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
            { "<leader>fq", "<cmd>Telescope ghq list<cr>", desc = "ghq repos" },
        },
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-telescope/telescope-ghq.nvim",
        },
        config = function(_, opts)
            local actions = require("telescope.actions")
            opts.defaults = vim.tbl_deep_extend("force", opts.defaults or {}, {
                mappings = {
                    i = {
                        ["\\"] = actions.select_vertical,
                        ["|"] = actions.select_vertical,
                        ["-"] = actions.select_horizontal,
                    },
                    n = {
                        ["\\"] = actions.select_vertical,
                        ["|"] = actions.select_vertical,
                        ["-"] = actions.select_horizontal,
                    },
                },
            })
            local telescope = require("telescope")
            telescope.setup(opts)
            telescope.load_extension("ghq")
        end,
    },

    -- Treesitter
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        event = { "BufReadPost", "BufNewFile" },
        opts = {
            ensure_installed = {
                "bash",
                "lua",
                "markdown",
                "nix",
                "python",
                "typescript",
                "javascript",
                "tsx",
                "jsx",
                "json",
                "yaml",
                "toml",
            },
            highlight = { enable = true },
            indent = { enable = true },
        },
        config = function(_, opts)
            local ok, ts_configs = pcall(require, "nvim-treesitter.configs")
            if not ok then
                vim.notify("nvim-treesitter is not available. Run :Lazy sync and restart Neovim.", vim.log.levels.WARN)
                return
            end
            ts_configs.setup(opts)
        end,
    },

    -- Git signs
    {
        "lewis6991/gitsigns.nvim",
        event = { "BufReadPre", "BufNewFile" },
        opts = {},
    },

    -- Mode indicator via cursorline background color
    {
        "mvllow/modes.nvim",
        event = "ModeChanged",
        opts = {
            colors = {
                copy = "#f9e2af",
                delete = "#f38ba8",
                insert = "#89dceb",
                visual = "#cba6f7",
            },
            line_opacity = {
                copy = 0.4,
                delete = 0.4,
                insert = 0.4,
                visual = 0.4,
            },
        },
    },

    -- Which-key
    {
        "folke/which-key.nvim",
        event = "VeryLazy",
        opts = {},
    },

    -- Comment
    {
        "numToStr/Comment.nvim",
        keys = {
            { "gcc", mode = "n", desc = "Comment line" },
            { "gc", mode = "v", desc = "Comment selection" },
        },
        opts = {},
    },

    -- Autopairs
    {
        "windwp/nvim-autopairs",
        event = "InsertEnter",
        opts = {},
    },

    -- Surround
    {
        "kylechui/nvim-surround",
        event = "VeryLazy",
        opts = {},
    },

    -- Indent guides
    {
        "lukas-reineke/indent-blankline.nvim",
        main = "ibl",
        event = { "BufReadPost", "BufNewFile" },
        opts = {},
    },

    -- Terminal-mode escape: jk → Normal-mode (faster than <C-\><C-n>)
    {
        "max397574/better-escape.nvim",
        event = { "InsertEnter", "TermOpen" },
        opts = {
            timeout = 100,
            default_mappings = false,
            mappings = {
                i = { j = { k = "<ESC>" } },
                t = { j = { k = "<C-\\><C-n>" } },
            },
        },
    },

    -- UI utilities + lazygit float
    {
        "folke/snacks.nvim",
        lazy = false,
        priority = 900,
        keys = {
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
                        -- Windows: bypass Snacks.lazygit; use open() not toggle().
                        -- Unset $NVIM so lazygit doesn't attempt nvim-remote at startup.
                        Snacks.terminal.open({ "lazygit" }, {
                            cwd = root,
                            env = { NVIM = "" },
                            win = { style = "lazygit" },
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
                        Snacks.terminal({ "lazygit", "log" }, { cwd = root, win = { style = "lazygit" } })
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
        },
        opts = {
            lazygit = { enabled = true },
            terminal = { enabled = true },
            picker = { enabled = true },
        },
    },

    -- AI sidekick: AI CLI terminal (claude/codex/gemini/opencode)
    {
        "folke/sidekick.nvim",
        event = "VeryLazy",
        dependencies = { "folke/snacks.nvim" },
        keys = {
            {
                "<C-.>",
                function()
                    require("sidekick.cli").focus()
                end,
                mode = { "n", "t", "i", "x" },
                desc = "Sidekick focus",
            },
            {
                "<leader>aa",
                function()
                    require("sidekick.cli").toggle({ name = "claude" })
                end,
                desc = "Sidekick toggle Claude (default)",
            },
            {
                "<leader>as",
                function()
                    require("sidekick.cli").select()
                end,
                desc = "Sidekick select CLI",
            },
            {
                "<leader>ad",
                function()
                    require("sidekick.cli").close()
                end,
                desc = "Sidekick detach CLI",
            },
            {
                "<leader>at",
                function()
                    require("sidekick.cli").send({ msg = "{this}" })
                end,
                mode = { "x", "n" },
                desc = "Sidekick send this",
            },
            {
                "<leader>af",
                function()
                    require("sidekick.cli").send({ msg = "{file}" })
                end,
                desc = "Sidekick send file",
            },
            {
                "<leader>av",
                function()
                    require("sidekick.cli").send({ msg = "{selection}" })
                end,
                mode = { "x" },
                desc = "Sidekick send selection",
            },
            {
                "<leader>ap",
                function()
                    require("sidekick.cli").prompt()
                end,
                mode = { "n", "x" },
                desc = "Sidekick prompt library",
            },
        },
        opts = {
            win = {
                layout = "right",
            },
            cli = {
                mux = {
                    backend = "tmux",
                    enabled = false,
                },
                tools = vim.tbl_extend("force", {
                    aider = false,
                    amazon_q = false,
                    copilot = false,
                    crush = false,
                    cursor = false,
                    grok = false,
                    pi = false,
                    qwen = false,
                }, vim.fn.has("unix") == 1 and {
                    claude = { cmd = { "env", "-u", "NVIM", "claude" } },
                } or {}),
            },
        },
    },

    -- Tmux pane navigation (C-h/j/k/l shared with nvim windows)
    {
        "christoomey/vim-tmux-navigator",
        cmd = { "TmuxNavigateLeft", "TmuxNavigateDown", "TmuxNavigateUp", "TmuxNavigateRight" },
    },

    -- Devcontainer
    {
        "erichlf/devcontainer-cli.nvim",
        dependencies = { "akinsho/toggleterm.nvim" },
        keys = {
            { "<leader>du", "<cmd>DevcontainerUp<cr>", desc = "Devcontainer up" },
            { "<leader>dc", "<cmd>DevcontainerExec bash<cr>", desc = "Devcontainer shell" },
            { "<leader>dd", "<cmd>DevcontainerDown<cr>", desc = "Devcontainer down" },
            { "<leader>dt", "<cmd>DevcontainerToggle<cr>", desc = "Devcontainer toggle log" },
        },
        opts = {
            dotfiles_repository = "https://github.com/rurusasu/dotfiles",
            dotfiles_branch = "main",
            dotfiles_targetPath = "~/.dotfiles",
        },
    },

    -- LSP: configurations
    -- Uses nvim 0.11+ `vim.lsp.config()` / `vim.lsp.enable()`. The legacy
    -- `require("lspconfig")[name].setup()` flow prints a deprecation warning
    -- and will be removed in nvim-lspconfig v3.0.0. nvim-lspconfig is still
    -- the source of bundled server defaults (`cmd`, `filetypes`, etc.).
    {
        "neovim/nvim-lspconfig",
        event = { "BufReadPre", "BufNewFile" },
        dependencies = { "hrsh7th/cmp-nvim-lsp" },
        config = function()
            local capabilities = require("cmp_nvim_lsp").default_capabilities()

            -- nvim 0.11+: use LspAttach autocmd instead of on_attach in vim.lsp.config
            vim.api.nvim_create_autocmd("LspAttach", {
                callback = function(args)
                    local bufnr = args.buf
                    local map = function(keys, func, desc)
                        vim.keymap.set("n", keys, func, { buffer = bufnr, desc = desc })
                    end
                    -- gd: LSP definition if supported, else telescope grep across files
                    map("gd", function()
                        local clients = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/definition" })
                        if #clients > 0 then
                            vim.lsp.buf.definition()
                        else
                            require("telescope.builtin").grep_string({ word_match = "-w" })
                        end
                    end, "Go to definition")
                    map("gr", vim.lsp.buf.references, "References")
                    map("K", vim.lsp.buf.hover, "Hover docs")
                    map("<leader>rn", vim.lsp.buf.rename, "Rename")
                    map("<leader>ca", vim.lsp.buf.code_action, "Code action")
                    map("<leader>f", function()
                        vim.lsp.buf.format({ async = true })
                    end, "Format")
                end,
            })

            -- Defaults applied to every server via the '*' wildcard.
            vim.lsp.config("*", {
                capabilities = capabilities,
            })

            local servers = {
                nixd = {
                    settings = {
                        nixd = {
                            formatting = { command = { "nixfmt" } },
                            options = {
                                nixos = {
                                    expr = '(builtins.getFlake (builtins.getEnv "HOME" + "/.dotfiles")).nixosConfigurations.nixos.options',
                                },
                            },
                        },
                    },
                },
                gopls = {
                    settings = {
                        gopls = {
                            usePlaceholders = true,
                            semanticTokens = true,
                            staticcheck = true,
                            gofumpt = true,
                            hints = {
                                assignVariableTypes = true,
                                compositeLiteralFields = true,
                                compositeLiteralTypes = true,
                                constantValues = true,
                                functionTypeParameters = true,
                                parameterNames = true,
                                rangeVariableTypes = true,
                            },
                            analyses = {
                                unusedparams = true,
                                shadow = true,
                                nilness = true,
                                unusedwrite = true,
                                useany = true,
                            },
                        },
                    },
                },
                rust_analyzer = {
                    settings = {
                        ["rust-analyzer"] = {
                            checkOnSave = true,
                            check = { command = "clippy" },
                            inlayHints = {
                                bindingModeHints = { enable = true },
                                closureCaptureHints = { enable = true },
                                closureReturnTypeHints = { enable = "always" },
                                lifetimeElisionHints = { enable = "skip_trivial" },
                                typeHints = { hideNamedConstructor = false },
                            },
                            procMacro = { enable = true },
                            cargo = { allFeatures = true, buildScripts = { enable = true } },
                        },
                    },
                },
                oxlint = {
                    cmd = { "oxlint", "--lsp" },
                    filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "vue", "svelte" },
                    root_markers = { "package.json", ".git" },
                },
                yamlls = {
                    settings = {
                        yaml = {
                            format = { enable = true },
                            validate = true,
                            completion = true,
                            hover = true,
                            schemaStore = { enable = true },
                        },
                    },
                },
                taplo = {},
                bashls = {
                    settings = {
                        bashIde = {
                            globPattern = "**/*@(.sh|.bash)",
                            enableSourceErrorDiagnostics = true,
                        },
                    },
                },
                lua_ls = {
                    settings = {
                        Lua = {
                            runtime = { version = "LuaJIT" },
                            diagnostics = { globals = { "vim" } },
                            workspace = { checkThirdParty = false },
                            telemetry = { enable = false },
                        },
                    },
                },
                ts_ls = {},
                marksman = {},
                ruff = {},
                ty = {
                    cmd = { "ty", "server" },
                    filetypes = { "python" },
                    root_markers = { "pyproject.toml", "setup.py", "setup.cfg", ".git" },
                },
            }

            for name, cfg in pairs(servers) do
                vim.lsp.config(name, cfg)
                vim.lsp.enable(name)
            end
        end,
    },

    -- Completion
    {
        "hrsh7th/nvim-cmp",
        event = "InsertEnter",
        dependencies = {
            "hrsh7th/cmp-nvim-lsp",
            "hrsh7th/cmp-buffer",
            "hrsh7th/cmp-path",
            "L3MON4D3/LuaSnip",
            "saadparwaiz1/cmp_luasnip",
        },
        config = function()
            local cmp = require("cmp")
            local luasnip = require("luasnip")
            cmp.setup({
                snippet = {
                    expand = function(args)
                        luasnip.lsp_expand(args.body)
                    end,
                },
                mapping = cmp.mapping.preset.insert({
                    ["<C-Space>"] = cmp.mapping.complete(),
                    ["<CR>"] = cmp.mapping.confirm({ select = false }),
                    ["<Tab>"] = cmp.mapping(function(fallback)
                        if cmp.visible() then
                            cmp.select_next_item()
                        elseif luasnip.expand_or_jumpable() then
                            luasnip.expand_or_jump()
                        else
                            fallback()
                        end
                    end, { "i", "s" }),
                    ["<S-Tab>"] = cmp.mapping(function(fallback)
                        if cmp.visible() then
                            cmp.select_prev_item()
                        else
                            fallback()
                        end
                    end, { "i", "s" }),
                }),
                sources = cmp.config.sources(
                    { { name = "nvim_lsp" }, { name = "luasnip" } },
                    { { name = "buffer" }, { name = "path" } }
                ),
            })
        end,
    },

    -- Floating file info per window
    {
        "b0o/incline.nvim",
        event = "VeryLazy",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
            local devicons = require("nvim-web-devicons")
            local c = {
                bg = "#313244",
                fg = "#cdd6f4",
                dim = "#7f849c",
                error = "#f38ba8",
                warn = "#fab387",
                info = "#89b4fa",
            }
            local generic_set = {}
            for _, n in ipairs({
                "init.lua",
                "init.vim",
                "init.ts",
                "init.js",
                "index.ts",
                "index.js",
                "index.tsx",
                "index.jsx",
                "main.rs",
                "main.go",
                "main.py",
                "main.c",
                "main.cpp",
                "mod.rs",
                "lib.rs",
            }) do
                generic_set[n] = true
            end

            require("incline").setup({
                window = {
                    padding = 1,
                    margin = { horizontal = 1, vertical = 0 },
                    placement = { horizontal = "right", vertical = "bottom" },
                    options = { winblend = 0 },
                },
                render = function(props)
                    local bufnr = props.buf
                    if vim.bo[bufnr].buftype == "terminal" then
                        return false
                    end
                    local focused = props.focused
                    local fname = vim.api.nvim_buf_get_name(bufnr)
                    local tail = fname ~= "" and vim.fn.fnamemodify(fname, ":t") or "[No Name]"
                    local name = tail
                    if generic_set[tail] then
                        local parent = vim.fn.fnamemodify(fname, ":h:t")
                        if parent ~= "" and parent ~= "." then
                            name = parent .. "/" .. tail
                        end
                    end

                    local icon, icon_color =
                        devicons.get_icon_color(tail, vim.fn.fnamemodify(fname, ":e"), { default = true })
                    icon = icon or ""
                    icon_color = icon_color or c.fg
                    local modified = vim.bo[bufnr].modified

                    local result = {}
                    if focused then
                        local diag_specs = {
                            { vim.diagnostic.severity.ERROR, "⊘", c.error },
                            { vim.diagnostic.severity.WARN, "△", c.warn },
                            { vim.diagnostic.severity.INFO, "⊙", c.info },
                        }
                        local any = false
                        for _, spec in ipairs(diag_specs) do
                            local count = #vim.diagnostic.get(bufnr, { severity = spec[1] })
                            if count > 0 then
                                result[#result + 1] = { spec[2] .. " " .. count .. " ", guifg = spec[3] }
                                any = true
                            end
                        end
                        if any then
                            result[#result + 1] = { "| ", guifg = c.dim }
                        end
                    end

                    result[#result + 1] = { icon .. " ", guifg = focused and icon_color or c.dim }
                    result[#result + 1] = { name, guifg = focused and c.fg or c.dim }
                    if modified then
                        result[#result + 1] = { " ●", guifg = c.warn }
                    end

                    result.guibg = c.bg
                    return result
                end,
            })
        end,
    },
}
