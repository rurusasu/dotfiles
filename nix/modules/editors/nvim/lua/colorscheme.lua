-- 標準の Catppuccin は dark で Mocha、light で Latte を使う。
vim.opt.background = "dark"
vim.cmd.colorscheme("catppuccin")

-- ターミナルの背景を透過する。
vim.cmd("highlight Normal guibg=NONE ctermbg=NONE")
vim.cmd("highlight NormalNC guibg=NONE ctermbg=NONE")
