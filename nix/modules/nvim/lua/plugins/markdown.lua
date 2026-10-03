-- プラグインの設定は Home Manager の起動処理から呼び出す。
local M = {}

function M.setup()
    local opts = {}

    require("render-markdown").setup(opts)

    for _, key in ipairs({
        {
            "<leader>mp",
            function()
                require("render-markdown").toggle()
            end,
            desc = "Toggle Markdown rendering",
        },
    }) do
        vim.keymap.set(key.mode or "n", key[1], key[2], { desc = key.desc })
    end
end

return M
