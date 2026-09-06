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
            -- Avoid the former FocusGained refresh/select race (PR #263).
            -- <C-l> is reserved for window navigation; refresh manually with
            -- :lua require("oil.actions").refresh.callback() when needed.

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

    -- Autopairs
    {
        "windwp/nvim-autopairs",
        event = "InsertEnter",
        opts = { map_cr = false }, -- config.completion owns Enter acceptance.
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
