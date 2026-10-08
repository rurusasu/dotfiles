-- ログの保存先は初回起動時にも用意する。
vim.fn.mkdir(vim.fn.stdpath("cache"), "p")

require("devcontainer-cli").setup({
    dotfiles_repository = "https://github.com/rurusasu/dotfiles",
    dotfiles_branch = "main",
    dotfiles_targetPath = "~/.dotfiles",
})

local keys = {
    { "<leader>du", "<cmd>DevcontainerUp<cr>", desc = "Devcontainer up" },
    { "<leader>dc", "<cmd>DevcontainerExec bash<cr>", desc = "Devcontainer shell" },
    { "<leader>dd", "<cmd>DevcontainerDown<cr>", desc = "Devcontainer down" },
    { "<leader>dt", "<cmd>DevcontainerToggle<cr>", desc = "Devcontainer toggle log" },
}

for _, key in ipairs(keys) do
    vim.keymap.set(key.mode or "n", key[1], key[2], { desc = key.desc })
end
