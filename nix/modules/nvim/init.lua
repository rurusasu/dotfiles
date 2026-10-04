-- Home Manager がプラグイン設定より先に読み込む基本設定。
if vim.fn.has("nvim-0.12") == 0 then
    error("This configuration requires Neovim 0.12 or newer. Update the package before applying it.")
end

-- プラグインのキー設定より先にリーダーキーを指定する。
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Core Neovim options

local opt = vim.opt

-- Line numbers: relative on left, absolute on right
opt.number = true
opt.relativenumber = true
opt.statuscolumn = "%{v:lnum}  %=%{v:relnum?printf('%3d', v:relnum):'   '} "

-- Indentation
opt.tabstop = 2
opt.softtabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.smartindent = true

-- 矩形選択では、文字がない位置にもカーソルを移動できるようにする。
opt.virtualedit = "block"

-- Search
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true
-- 置換結果を入力中にプレビューし、画面外の変更も分割ウインドウに表示する。
opt.inccommand = "split"

-- Mouse: enable in all modes so floating windows can be dragged by title bar
opt.mouse = "a"

-- UI
-- コマンド未入力時はコマンドライン領域を隠す。
opt.cmdheight = 0
opt.termguicolors = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.wrap = true
opt.linebreak = true
opt.breakindent = true

-- タブ・行末の空白・改行しない空白を可視化する。
opt.list = true
opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }

-- Clear statusline (hide to gain code area; info moved to tmux/incline/modes)
opt.laststatus = 0
opt.statusline = "─"
opt.fillchars:append({ stl = "─", stlnc = "─" })

-- Clear winbar (use Snacks.picker for buffer switching instead)
opt.winbar = ""

-- Split behavior
opt.splitbelow = true
opt.splitright = true
-- 分割の開閉で、表示している行の位置が大きく変わらないようにする。
opt.splitkeep = "screen"

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

-- Windows: use PowerShell for :terminal, :!, and shell-backed plugin commands.
if vim.fn.has("win32") == 1 then
    local shell = vim.fn.executable("pwsh.exe") == 1 and "pwsh.exe" or "powershell.exe"
    opt.shell = shell
    opt.shelltemp = false

    local shellcmdflag = "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command "
        .. "[Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.UTF8Encoding]::new();"
        .. "$PSDefaultParameterValues['Out-File:Encoding']='utf8';"
    if shell == "pwsh.exe" then
        shellcmdflag = shellcmdflag .. "$PSStyle.OutputRendering='PlainText';"
    end

    opt.shellcmdflag = shellcmdflag
    opt.shellpipe = "> %s 2>&1"
    opt.shellredir = "> %s 2>&1"
    opt.shellquote = ""
    opt.shellxquote = ""
end

-- Undo persistence
opt.undofile = true
opt.undolevels = 10000

-- 未保存の変更がある場合は、終了やバッファ切り替え時に保存を確認する。
opt.confirm = true
-- 外部で変更されたファイルは、編集中の変更がない場合に再読み込みする。
opt.autoread = true

-- Performance
opt.updatetime = 250
opt.timeoutlen = 300

-- Completion options and snippet navigation live in config.completion.

-- Disable swap/backup
opt.swapfile = false
opt.backup = false

-- Windows: ensure ImageMagick and Poppler are in PATH for snacks image/PDF conversion.
-- winget installs to versioned dirs that may not reach nvim when launched from a shell
-- whose profile has not yet rebuilt PATH from the registry.
if vim.fn.has("win32") == 1 then
    local function prepend_path(dir)
        if vim.fn.isdirectory(dir) == 1 then
            vim.env.PATH = dir .. ";" .. vim.env.PATH
        end
    end

    prepend_path(vim.fn.expand("$LOCALAPPDATA") .. "/Microsoft/WinGet/Links")
    prepend_path(vim.fn.expand("$USERPROFILE") .. "/.cargo/bin")

    if vim.fn.executable("magick") == 0 then
        for _, dir in ipairs(vim.fn.glob("C:/Program Files/ImageMagick*", false, true)) do
            if vim.fn.isdirectory(dir) == 1 then
                vim.env.PATH = dir .. ";" .. vim.env.PATH
                break
            end
        end
    end
    if vim.fn.executable("pdftoppm") == 0 then
        -- WinGet installs Poppler as: oschwartz10612.Poppler_.../poppler-X.Y.Z/Library/bin
        local pattern = vim.fn.expand("$LOCALAPPDATA")
            .. "/Microsoft/WinGet/Packages/oschwartz10612.Poppler*/*/Library/bin"
        for _, dir in ipairs(vim.fn.glob(pattern, false, true)) do
            if vim.fn.isdirectory(dir) == 1 then
                vim.env.PATH = dir .. ";" .. vim.env.PATH
                break
            end
        end
    end
end

-- Restore the terminal for the retained WezTerm/Windows Terminal exit workaround.
-- Route control sequences through the UI, never through headless stdout.
vim.api.nvim_create_autocmd("VimLeave", {
    callback = function()
        for _, ui in ipairs(vim.api.nvim_list_uis()) do
            if ui.stdout_tty then
                vim.api.nvim_ui_send("\027[?1049l\027[H\027[2J")
                break
            end
        end
    end,
})

-- 補助機能は同じ Nix モジュール配下の Lua ファイルから読み込む。
require("colorscheme")
require("config.autocmds").setup()
require("config.keymaps")
require("config.osc7").setup()
require("config.completion").setup()
require("config.treesitter").setup()
