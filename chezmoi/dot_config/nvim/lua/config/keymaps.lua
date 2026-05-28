-- Keymaps

local map = vim.keymap.set

-- Better window navigation (overridden by vim-tmux-navigator with TmuxNavigate* at startup)
map("n", "<C-h>", "<C-w>h", { desc = "Go to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Go to lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Go to upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Go to right window" })

-- Resize windows
map("n", "<C-Up>", "<cmd>resize +2<cr>", { desc = "Increase window height" })
map("n", "<C-Down>", "<cmd>resize -2<cr>", { desc = "Decrease window height" })
map("n", "<C-Left>", "<cmd>vertical resize -2<cr>", { desc = "Decrease window width" })
map("n", "<C-Right>", "<cmd>vertical resize +2<cr>", { desc = "Increase window width" })

-- Move lines
map("n", "<A-j>", "<cmd>m .+1<cr>==", { desc = "Move line down" })
map("n", "<A-k>", "<cmd>m .-2<cr>==", { desc = "Move line up" })
map("v", "<A-j>", ":m '>+1<cr>gv=gv", { desc = "Move selection down" })
map("v", "<A-k>", ":m '<-2<cr>gv=gv", { desc = "Move selection up" })

-- Buffer navigation
map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Prev buffer" })
map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "<leader>bd", "<cmd>bdelete<cr>", { desc = "Delete buffer" })

-- Clear search highlight
map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })

-- Better indenting
map("v", "<", "<gv", { desc = "Indent left" })
map("v", ">", ">gv", { desc = "Indent right" })

-- Save file
map("n", "<leader>w", "<cmd>w<cr>", { desc = "Save file" })
map("n", "<C-s>", "<cmd>w<cr>", { desc = "Save file" })

-- Quit
map("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit" })
map("n", "<leader>Q", "<cmd>qa!<cr>", { desc = "Quit all" })

-- Diagnostics
map("n", "<leader>e", vim.diagnostic.open_float, { desc = "Show diagnostic" })

-- File explorer
map("n", "-", "<cmd>Oil<cr>", { desc = "Open parent directory" })

-- Terminal mode
map("t", "jk", "<C-\\><C-n>", { desc = "Exit terminal mode" })

-- Float terminal resize (Alt+ 単キー)。nvim の terminal mode は prefix mapping
-- が動作しにくいため、確実に届く single keystroke の Alt 系を採用。
-- Shift キーが必要な記号 (`+` / `_`) を使うことで、視覚的にも拡大/縮小と
-- 結びつきやすい。リセットは少なくとも今は keymap 化していない:
-- `:lua require("config.float_term").reset()` で呼び出し可能。
local function fterm_grow()
    require("config.float_term").grow()
end
local function fterm_shrink()
    require("config.float_term").shrink()
end

map({ "n", "t" }, "<M-+>", fterm_grow, { desc = "Float term: grow (+5%)" })
map({ "n", "t" }, "<M-_>", fterm_shrink, { desc = "Float term: shrink (-5%)" })

-- Move floating window (Alt+Shift+HJKL)
local function move_float(dr, dc)
    local win = vim.api.nvim_get_current_win()
    local cfg = vim.api.nvim_win_get_config(win)
    if cfg.relative == "" then
        return
    end
    cfg.row = (cfg.row or 0) + dr
    cfg.col = (cfg.col or 0) + dc
    vim.api.nvim_win_set_config(win, cfg)
    require("config.float_persist").save(win)
end
map("t", "<A-H>", function()
    move_float(0, -3)
end, { desc = "Float: move left" })
map("t", "<A-J>", function()
    move_float(3, 0)
end, { desc = "Float: move down" })
map("t", "<A-K>", function()
    move_float(-3, 0)
end, { desc = "Float: move up" })
map("t", "<A-L>", function()
    move_float(0, 3)
end, { desc = "Float: move right" })

-- Unified window management (same characters as tmux/terminal layers)
map("n", "<leader>\\", "<cmd>vsplit<cr>", { desc = "Vertical split" })
map("n", "<leader>-", "<cmd>split<cr>", { desc = "Horizontal split" })
map("n", "<leader>x", "<cmd>q<cr>", { desc = "Close window" })
map("n", "<leader>h", "<cmd>bprevious<cr>", { desc = "Prev buffer" })
map("n", "<leader>l", "<cmd>bnext<cr>", { desc = "Next buffer" })

-- Terminal mode: use TmuxNavigate so boundary-crossing to tmux panes works
map("t", "<C-h>", "<C-\\><C-n>:TmuxNavigateLeft<cr>", { desc = "Go to left window" })
map("t", "<C-j>", "<C-\\><C-n>:TmuxNavigateDown<cr>", { desc = "Go to lower window" })
map("t", "<C-k>", "<C-\\><C-n>:TmuxNavigateUp<cr>", { desc = "Go to upper window" })
map("t", "<C-l>", "<C-\\><C-n>:TmuxNavigateRight<cr>", { desc = "Go to right window" })

-- Open terminal in a 15-line split at the bottom
vim.api.nvim_create_user_command("Term", function()
    vim.cmd("botright 15split | terminal")
    vim.cmd("startinsert")
end, { desc = "Open terminal in bottom split" })

require("config.float_persist").setup()

-- Redirect :terminal (typed at start of command line) to :Term.
-- getcmdpos() guard prevents expansion mid-command (e.g. :edit terminal stays intact).
vim.cmd([[cabbrev <expr> terminal (getcmdtype() == ':' && getcmdpos() <= 9) ? 'Term' : 'terminal']])

-- If a terminal opens alongside other windows (plugins, scripted :terminal),
-- snap it to the bottom. Single-window case is handled by :Term above.
vim.api.nvim_create_autocmd("TermOpen", {
    callback = function()
        if vim.fn.winnr("$") > 1 then
            vim.cmd("wincmd J")
            vim.cmd("resize 15")
        end
    end,
})
