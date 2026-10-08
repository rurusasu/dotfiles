require("better_escape").setup({
    timeout = 100,
    default_mappings = false,
    mappings = {
        i = { j = { k = "<ESC>" } },
        t = { j = { k = "<C-\\><C-n>" } },
    },
})
