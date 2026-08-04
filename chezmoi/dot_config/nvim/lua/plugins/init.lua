-- Plugin specifications for lazy.nvim

return {
    -- Colorscheme
    {
        "catppuccin/nvim",
        name = "catppuccin",
        lazy = false,
        priority = 1000,
        config = function()
            require("catppuccin").setup({ flavour = "mocha", transparent_background = true })
            vim.cmd.colorscheme("catppuccin-mocha")
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
            delete_to_trash = true,
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
                ["<Esc>"] = "actions.close",
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
            -- (削除: PR #263 で入れた FocusGained refresh は user の select 操作と
            -- 衝突して `cache.lua:138: Entry X missing parent url` を起こす race
            -- condition があったため撤回。WSL /mnt の外部変更反映は手動 `<C-l>`
            -- (oil default の refresh) で対応する。)

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
                    -- gd: LSP definition if supported, else snacks grep for word under cursor
                    map("gd", function()
                        local clients = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/definition" })
                        if #clients > 0 then
                            vim.lsp.buf.definition()
                        else
                            Snacks.picker.grep_word()
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

            local format_on_save_clients = {
                python = { ruff = true },
                rust = { rust_analyzer = true },
            }

            vim.api.nvim_create_autocmd("BufWritePre", {
                group = vim.api.nvim_create_augroup("DotfilesFormatOnSave", { clear = true }),
                pattern = { "*.py", "*.rs" },
                callback = function(args)
                    local ft = vim.bo[args.buf].filetype
                    local allowed_clients = format_on_save_clients[ft]
                    if not allowed_clients then
                        return
                    end

                    local has_formatter = false
                    for _, client in
                        ipairs(vim.lsp.get_clients({
                            bufnr = args.buf,
                            method = "textDocument/formatting",
                        }))
                    do
                        if allowed_clients[client.name] then
                            has_formatter = true
                            break
                        end
                    end

                    if not has_formatter then
                        return
                    end

                    vim.lsp.buf.format({
                        bufnr = args.buf,
                        async = false,
                        timeout_ms = 3000,
                        filter = function(client)
                            return allowed_clients[client.name] == true
                        end,
                    })
                end,
            })

            -- Defaults applied to every server via the '*' wildcard.
            vim.lsp.config("*", {
                capabilities = capabilities,
            })

            local is_win = vim.fn.has("win32") == 1
            local nix_lsp_proxy = vim.fn.expand("~/.local/bin/nix-lsp-wsl-proxy.mjs")

            local servers = {
                nixd = {
                    cmd = is_win and { "node", nix_lsp_proxy } or nil,
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
                if name ~= "nixd" then
                    vim.lsp.enable(name)
                end
            end
            vim.lsp.enable("nixd")
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
            local c = {
                fg = "#c0caf5",
                dim = "#565f89",
                error = "#f7768e",
                warn = "#e0af68",
                info = "#7dcfff",
            }
            local set_hl = function()
                vim.api.nvim_set_hl(0, "InclineActive", { bg = "#2d2f3f", fg = c.fg })
                vim.api.nvim_set_hl(0, "InclineInactive", { bg = "#2d2f3f", fg = c.dim })
            end
            set_hl()
            vim.api.nvim_create_autocmd("ColorScheme", { callback = set_hl })

            local devicons = require("nvim-web-devicons")
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
                    winhighlight = {
                        active = { Normal = "InclineActive" },
                        inactive = { Normal = "InclineInactive" },
                    },
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

                    local icon, icon_color
                    if fname ~= "" then
                        icon, icon_color =
                            devicons.get_icon_color(tail, vim.fn.fnamemodify(fname, ":e"), { default = true })
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

                    result[#result + 1] = { icon .. " ", guifg = icon_color }
                    result[#result + 1] = { name, guifg = focused and c.fg or c.dim }
                    if vim.bo[bufnr].modified then
                        result[#result + 1] = { " ●", guifg = c.warn }
                    end
                    return result
                end,
            })
        end,
    },
}
