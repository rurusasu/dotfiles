local function resize_sidekick_cli(terminal, delta)
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

local function resize_sidekick_cli_toward(terminal, direction)
    local layout = terminal.opts and terminal.opts.layout or "right"
    if layout == "top" or layout == "bottom" then
        return
    end

    local delta = direction == "left" and 5 or -5
    if layout == "left" then
        delta = -delta
    end
    resize_sidekick_cli(terminal, delta)
end

return {
    -- AI sidekick: AI CLI terminal (codex/gemini/opencode)
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
                "<leader>as",
                function()
                    require("sidekick.cli").select({ focus = true })
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
            cli = {
                win = {
                    layout = "right",
                    keys = {
                        resize_grow = {
                            "<M-+>",
                            function(terminal)
                                resize_sidekick_cli(terminal, 5)
                            end,
                            mode = "nt",
                            desc = "Sidekick grow window",
                        },
                        resize_shrink = {
                            "<M-_>",
                            function(terminal)
                                resize_sidekick_cli(terminal, -5)
                            end,
                            mode = "nt",
                            desc = "Sidekick shrink window",
                        },
                        resize_left = {
                            "<C-S-h>",
                            function(terminal)
                                resize_sidekick_cli_toward(terminal, "left")
                            end,
                            mode = "nt",
                            desc = "Sidekick resize left",
                        },
                        resize_right = {
                            "<C-S-l>",
                            function(terminal)
                                resize_sidekick_cli_toward(terminal, "right")
                            end,
                            mode = "nt",
                            desc = "Sidekick resize right",
                        },
                    },
                },
                mux = {
                    backend = "tmux",
                    enabled = false,
                },
            },
        },
    },
}
