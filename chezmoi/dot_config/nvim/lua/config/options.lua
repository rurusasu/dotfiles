-- Core Neovim options

local opt = vim.opt

-- Line numbers: relative on left, absolute on right
opt.number = true
opt.relativenumber = true
opt.statuscolumn = "%{v:lnum}  %=%{v:relnum?printf('%3d', v:relnum):'   '} "

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

-- Mouse: enable in all modes so floating windows can be dragged by title bar
opt.mouse = "a"

-- UI
opt.termguicolors = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.wrap = true
opt.linebreak = true
opt.breakindent = true

-- Clear statusline (hide to gain code area; info moved to tmux/incline/modes)
opt.laststatus = 0
opt.statusline = "─"
opt.fillchars:append({ stl = "─", stlnc = "─" })

-- Clear winbar (use Snacks.picker for buffer switching instead)
opt.winbar = ""

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

-- Windows: ensure ImageMagick and Poppler are in PATH for snacks image/PDF conversion.
-- winget installs to versioned dirs that may not reach nvim when launched from a shell
-- whose profile has not yet rebuilt PATH from the registry.
if vim.fn.has("win32") == 1 then
    if vim.fn.executable("magick") == 0 then
        for _, dir in ipairs(vim.fn.glob("C:/Program Files/ImageMagick*", false, true)) do
            if vim.fn.isdirectory(dir) == 1 then
                vim.env.PATH = dir .. ";" .. vim.env.PATH
                break
            end
        end
    end
    if vim.fn.executable("pdftoppm") == 0 then
        local pattern = vim.fn.expand("$LOCALAPPDATA") .. "/Microsoft/WinGet/Packages/oschwartz10612.Poppler*/Library/bin"
        for _, dir in ipairs(vim.fn.glob(pattern, false, true)) do
            if vim.fn.isdirectory(dir) == 1 then
                vim.env.PATH = dir .. ";" .. vim.env.PATH
                break
            end
        end
    end
end

-- Restore terminal on exit: explicitly switch off alternate screen so the
-- shell is visible immediately after :q (fixes ghost-screen in WezTerm/WT)
vim.api.nvim_create_autocmd("VimLeave", {
    callback = function()
        io.write("\027[?1049l\027[H\027[2J")
        io.flush()
    end,
})
