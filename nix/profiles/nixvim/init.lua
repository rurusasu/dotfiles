-- Neovim configuration for VSCode integration and native use
-- Location: ~/.config/nvim/init.lua

-- Leader keys
vim.g.mapleader = ' '
vim.g.maplocalleader = ','

-- Basic settings that work everywhere
vim.opt.clipboard = 'unnamedplus'  -- System clipboard integration
vim.opt.ignorecase = true          -- Case-insensitive search
vim.opt.smartcase = true           -- Case-sensitive if uppercase in search
vim.opt.hlsearch = true            -- Highlight search results
vim.opt.incsearch = true           -- Incremental search

-- Conditional configuration based on VSCode or native Neovim
if vim.g.vscode then
    -- ========================================
    -- VSCode Neovim Configuration
    -- ========================================

    local vscode = require('vscode-neovim')

    -- ========================================
    -- VSCode Command Mappings
    -- ========================================

    -- File Navigation
    vim.keymap.set('n', '<leader>ff', function()
        vscode.action('workbench.action.quickOpen')
    end, { desc = 'Quick Open Files' })

    vim.keymap.set('n', '<leader>fg', function()
        vscode.action('workbench.action.findInFiles')
    end, { desc = 'Find in Files' })

    vim.keymap.set('n', '<leader>fr', function()
        vscode.action('workbench.action.openRecent')
    end, { desc = 'Recent Files' })

    -- Code Actions
    vim.keymap.set('n', '<leader>ca', function()
        vscode.action('editor.action.quickFix')
    end, { desc = 'Code Actions' })

    vim.keymap.set('n', '<leader>rn', function()
        vscode.action('editor.action.rename')
    end, { desc = 'Rename Symbol' })

    vim.keymap.set('n', '<leader>rf', function()
        vscode.action('editor.action.formatDocument')
    end, { desc = 'Format Document' })

    -- Go To
    vim.keymap.set('n', 'gd', function()
        vscode.action('editor.action.revealDefinition')
    end, { desc = 'Go to Definition' })

    vim.keymap.set('n', 'gD', function()
        vscode.action('editor.action.revealDeclaration')
    end, { desc = 'Go to Declaration' })

    vim.keymap.set('n', 'gi', function()
        vscode.action('editor.action.goToImplementation')
    end, { desc = 'Go to Implementation' })

    vim.keymap.set('n', 'gr', function()
        vscode.action('editor.action.goToReferences')
    end, { desc = 'Go to References' })

    vim.keymap.set('n', 'gt', function()
        vscode.action('editor.action.goToTypeDefinition')
    end, { desc = 'Go to Type Definition' })

    -- Comment Toggle
    vim.keymap.set('n', 'gcc', function()
        vscode.action('editor.action.commentLine')
    end, { desc = 'Comment Line' })

    vim.keymap.set('v', 'gc', function()
        vscode.action('editor.action.commentLine')
    end, { desc = 'Comment Selection' })

    -- Explorer
    vim.keymap.set('n', '<leader>e', function()
        vscode.action('workbench.view.explorer')
    end, { desc = 'Toggle Explorer' })

    -- Terminal
    vim.keymap.set('n', '<leader>tt', function()
        vscode.action('workbench.action.terminal.toggleTerminal')
    end, { desc = 'Toggle Terminal' })

    vim.keymap.set('n', '<leader>tn', function()
        vscode.action('workbench.action.terminal.new')
    end, { desc = 'New Terminal' })

    -- Git
    vim.keymap.set('n', '<leader>gs', function()
        vscode.action('workbench.view.scm')
    end, { desc = 'Git Status' })

    vim.keymap.set('n', '<leader>gd', function()
        vscode.action('git.openChange')
    end, { desc = 'Git Diff' })

    vim.keymap.set('n', '<leader>gb', function()
        vscode.action('git.blame')
    end, { desc = 'Git Blame' })

    -- Search
    vim.keymap.set('n', '<leader>/', function()
        vscode.action('workbench.action.findInFiles')
    end, { desc = 'Search in Files' })

    -- Errors/Problems
    vim.keymap.set('n', '<leader>xx', function()
        vscode.action('workbench.actions.view.problems')
    end, { desc = 'Show Problems' })

    vim.keymap.set('n', '[d', function()
        vscode.action('editor.action.marker.prev')
    end, { desc = 'Previous Diagnostic' })

    vim.keymap.set('n', ']d', function()
        vscode.action('editor.action.marker.next')
    end, { desc = 'Next Diagnostic' })

    -- Window Management
    vim.keymap.set('n', '<leader>wh', function()
        vscode.action('workbench.action.focusLeftGroup')
    end, { desc = 'Focus Left' })

    vim.keymap.set('n', '<leader>wl', function()
        vscode.action('workbench.action.focusRightGroup')
    end, { desc = 'Focus Right' })

    vim.keymap.set('n', '<leader>wv', function()
        vscode.action('workbench.action.splitEditorRight')
    end, { desc = 'Split Vertical' })

    vim.keymap.set('n', '<leader>ws', function()
        vscode.action('workbench.action.splitEditorDown')
    end, { desc = 'Split Horizontal' })

    vim.keymap.set('n', '<leader>wc', function()
        vscode.action('workbench.action.closeActiveEditor')
    end, { desc = 'Close Editor' })

    -- ========================================
    -- Custom Vim Behaviors
    -- ========================================

    -- Clear search highlight
    vim.keymap.set('n', '<leader>nh', ':noh<CR>', { desc = 'Clear Highlight', silent = true })

    -- Better line navigation with word wrap
    vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true })
    vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true })

    -- Stay in visual mode when indenting
    vim.keymap.set('v', '<', '<gv')
    vim.keymap.set('v', '>', '>gv')

    -- Move selected lines
    vim.keymap.set('v', 'J', ":m '>+1<CR>gv=gv")
    vim.keymap.set('v', 'K', ":m '<-2<CR>gv=gv")
else
    -- ========================================
    -- Native Neovim Configuration
    -- ========================================

    -- UI settings
    vim.opt.number = true
    vim.opt.relativenumber = true
    vim.opt.signcolumn = 'yes'
    vim.opt.cursorline = true

    -- Indentation
    vim.opt.tabstop = 2
    vim.opt.shiftwidth = 2
    vim.opt.expandtab = true
    vim.opt.smartindent = true

    -- Scrolling
    vim.opt.scrolloff = 8
    vim.opt.sidescrolloff = 8

    -- Native Neovim-specific plugins and LSP would go here
    -- require('plugins')
    -- require('lsp')
end
