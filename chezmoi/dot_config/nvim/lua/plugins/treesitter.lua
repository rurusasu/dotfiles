return {
    {
        "nvim-treesitter/nvim-treesitter",
        branch = "main",
        -- Nix supplies data-only parser/query files. Other installations use
        -- the plugin only for installation; highlighting is always native.
        enabled = not vim.env.DOTFILES_NVIM_TREESITTER,
        lazy = false,
        build = ":TSUpdate",
        config = function()
            local runtime = vim.api.nvim_get_runtime_file("treesitter.json", false)[1]
            local languages = vim.json.decode(table.concat(vim.fn.readfile(assert(runtime)), "\n"))
            local installer = require("nvim-treesitter")
            local install_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "site")
            installer.setup({ install_dir = install_dir })
            local installed = installer.get_installed("parsers")
            local queries = installer.get_installed("queries")
            local missing = vim.tbl_filter(function(lang)
                return not vim.list_contains(installed, lang)
                    or not vim.list_contains(queries, lang)
                    or vim.fn.filereadable(vim.fs.joinpath(install_dir, "queries", lang, "highlights.scm")) == 0
            end, languages)
            if #missing == 0 then
                return
            end
            if vim.fn.executable("tree-sitter") == 0 then
                vim.notify(
                    "Parser installation requires tree-sitter CLI >= 0.26.1 and a C compiler. See docs/chezmoi/neovim.md.",
                    vim.log.levels.WARN
                )
                return
            end
            -- A parser can survive a failed query install. Force repair of only
            -- incomplete languages instead of treating the binary as success.
            installer.install(missing, { force = true }):await(function(err, success)
                vim.schedule(function()
                    if err or success == false then
                        vim.notify(
                            "Parser installation failed: " .. tostring(err or "see :messages"),
                            vim.log.levels.ERROR
                        )
                        return
                    end
                    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                        if vim.api.nvim_buf_is_loaded(buf) then
                            require("config.treesitter").start(buf)
                        end
                    end
                end)
            end)
        end,
    },
}
