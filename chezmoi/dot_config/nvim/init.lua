-- Neovim configuration
-- Managed by chezmoi

-- Windows: prepend real Python to PATH so Mason (pip/pypi installs) bypass
-- the App Execution Alias stub in WindowsApps.
if vim.fn.has("win32") == 1 then
    local py = vim.fn.expand("$LOCALAPPDATA") .. "\\Programs\\Python\\Python313"
    vim.env.PATH = py .. "\\Scripts;" .. py .. ";" .. vim.env.PATH
end

-- Leader key (before lazy)
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Load core settings
require("config.options")
require("config.keymaps")
require("config.osc7").setup()

require("config.lazy")
