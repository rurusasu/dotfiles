-- Core Neovim options

local opt = vim.opt

-- Line numbers
opt.number = true
opt.relativenumber = true

-- Indentation
opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.smartindent = true

-- Search
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true

-- UI
opt.termguicolors = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.wrap = false

-- Split behavior
opt.splitbelow = true
opt.splitright = true

-- Clipboard: always use unnamedplus; in WSL route it through win32yank.exe
opt.clipboard = "unnamedplus"
if vim.fn.has("wsl") == 1 then
    vim.g.clipboard = {
        name = "win32yank",
        copy = { ["+"] = "win32yank.exe -i --crlf", ["*"] = "win32yank.exe -i --crlf" },
        paste = { ["+"] = "win32yank.exe -o --lf", ["*"] = "win32yank.exe -o --lf" },
        cache_enabled = 0,
    }
end

-- Undo persistence
opt.undofile = true
opt.undolevels = 10000

-- Performance
opt.updatetime = 250
opt.timeoutlen = 300

-- Completion
opt.completeopt = "menu,menuone,noselect"

-- Disable swap/backup
opt.swapfile = false
opt.backup = false

-- Restore terminal on exit: explicitly switch off alternate screen so the
-- shell is visible immediately after :q (fixes ghost-screen in WezTerm/WT)
vim.api.nvim_create_autocmd("VimLeave", {
    callback = function()
        io.write("\027[?1049l\027[H\027[2J")
        io.flush()
    end,
})
