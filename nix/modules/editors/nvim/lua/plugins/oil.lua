require("oil").setup({
    default_file_explorer = true,
    delete_to_trash = true,
    watch_for_changes = true,
    view_options = {
        show_hidden = true,
    },
    keymaps = {
        ["<Esc>"] = "actions.close",
    },
})

local keys = {
    { "-", "<cmd>Oil<cr>", desc = "Open Oil" },
}

for _, key in ipairs(keys) do
    vim.keymap.set(key.mode or "n", key[1], key[2], { desc = key.desc })
end
