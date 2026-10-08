require("render-markdown").setup()

local keys = {
    {
        "<leader>mp",
        function()
            require("render-markdown").toggle()
        end,
        desc = "Toggle Markdown rendering",
    },
}

for _, key in ipairs(keys) do
    vim.keymap.set(key.mode or "n", key[1], key[2], { desc = key.desc })
end
