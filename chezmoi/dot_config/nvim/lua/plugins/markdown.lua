return {
    {
        "MeanderingProgrammer/render-markdown.nvim",
        ft = "markdown",
        dependencies = { "nvim-tree/nvim-web-devicons" },
        opts = {},
        keys = {
            {
                "<leader>mp",
                function()
                    require("render-markdown").toggle()
                end,
                desc = "Toggle Markdown rendering",
            },
        },
    },
}
