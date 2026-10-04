-- プラグインの設定は Home Manager の起動処理から呼び出す。
local M = {}

function M.setup()
    -- ログの保存先は初回起動時にも用意する。
    vim.fn.mkdir(vim.fn.stdpath("cache"), "p")

    local opts = {
        dotfiles_repository = "https://github.com/rurusasu/dotfiles",
        dotfiles_branch = "main",
        dotfiles_targetPath = "~/.dotfiles",
    }

    require("devcontainer-cli").setup(opts)

    for _, key in ipairs({
        { "<leader>du", "<cmd>DevcontainerUp<cr>", desc = "Devcontainer up" },
        { "<leader>dc", "<cmd>DevcontainerExec bash<cr>", desc = "Devcontainer shell" },
        { "<leader>dd", "<cmd>DevcontainerDown<cr>", desc = "Devcontainer down" },
        { "<leader>dt", "<cmd>DevcontainerToggle<cr>", desc = "Devcontainer toggle log" },
    }) do
        vim.keymap.set(key.mode or "n", key[1], key[2], { desc = key.desc })
    end
end

return M
