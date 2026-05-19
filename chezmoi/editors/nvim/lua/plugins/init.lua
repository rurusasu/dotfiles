-- Plugin specifications for lazy.nvim

return {
    -- Colorscheme
    {
        "ellisonleao/gruvbox.nvim",
        lazy = false,
        priority = 1000,
        config = function()
            vim.cmd.colorscheme("gruvbox")
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
        },
        config = function(_, opts)
            require("oil").setup(opts)
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
        },
        dependencies = { "nvim-lua/plenary.nvim" },
        opts = {},
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

    -- Status line
    {
        "nvim-lualine/lualine.nvim",
        event = "VeryLazy",
        opts = {
            options = {
                theme = "gruvbox",
                component_separators = "|",
                section_separators = "",
            },
            sections = {
                lualine_b = { "branch", "diff", "diagnostics" },
                lualine_c = { { "filename", path = 1 } },
            },
        },
    },

    -- Git signs
    {
        "lewis6991/gitsigns.nvim",
        event = { "BufReadPre", "BufNewFile" },
        opts = {},
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

    -- AI coding assistant (codecompanion + ACP agents)
    {
        "olimorris/codecompanion.nvim",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-treesitter/nvim-treesitter",
        },
        cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions" },
        keys = {
            { "<leader>aa", "<cmd>CodeCompanionChat Toggle<cr>", desc = "AI chat toggle" },
            { "<leader>ai", "<cmd>CodeCompanion<cr>", mode = { "n", "v" }, desc = "AI inline" },
            { "<leader>ac", "<cmd>CodeCompanionActions<cr>", mode = { "n", "v" }, desc = "AI actions" },
        },
        opts = {
            adapters = {
                acp = {
                    claude_code = function()
                        return require("codecompanion.adapters").extend("claude_code", {
                            defaults = {
                                mcpServers = "inherit_from_config",
                            },
                        })
                    end,
                    codex = function()
                        return require("codecompanion.adapters").extend("codex", {
                            defaults = {
                                auth_method = "chatgpt",
                            },
                        })
                    end,
                },
            },
            interactions = {
                chat = {
                    adapter = "claude_code",
                    keymaps = {
                        send = {
                            modes = { n = "<CR>", i = "<C-CR>" },
                        },
                    },
                },
                inline = { adapter = "claude_code" },
            },
        },
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
    -- Uses nvim 0.12 built-in vim.lsp.enable() / LspAttach autocmd pattern.
    -- Mason removed; servers are managed by Nix (NixOS) or winget/pnpm (Windows).
    -- vim.fn.executable() guards ensure graceful degradation on any platform.
    {
        "neovim/nvim-lspconfig",
        event = { "BufReadPre", "BufNewFile" },
        config = function()
            vim.api.nvim_create_autocmd("LspAttach", {
                callback = function(args)
                    local client = vim.lsp.get_client_by_id(args.data.client_id)
                    local bufnr = args.buf
                    local map = function(keys, func, desc)
                        vim.keymap.set("n", keys, func, { buffer = bufnr, desc = desc })
                    end
                    map("gd", vim.lsp.buf.definition, "Go to definition")
                    map("gr", vim.lsp.buf.references, "References")
                    map("K", vim.lsp.buf.hover, "Hover docs")
                    map("<leader>rn", vim.lsp.buf.rename, "Rename")
                    map("<leader>ca", vim.lsp.buf.code_action, "Code action")
                    map("<leader>f", function()
                        vim.lsp.buf.format({ async = true })
                    end, "Format")
                    if client and client.supports_method("textDocument/completion") then
                        vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true })
                    end
                end,
            })

            local server_bins = {
                gopls = "gopls",
                rust_analyzer = "rust-analyzer",
                ts_ls = "typescript-language-server",
                yamlls = "yaml-language-server",
                taplo = "taplo",
                bashls = "bash-language-server",
                lua_ls = "lua-language-server",
                marksman = "marksman",
                ruff = "ruff",
                nixd = "nixd",
            }

            for name, exe in pairs(server_bins) do
                if vim.fn.executable(exe) == 1 then
                    vim.lsp.enable(name)
                end
            end
        end,
    },
}
