local Snacks = require("snacks")
local picker = require("config.snacks_picker")
local allocation = require("config.key_allocation")

-- Share repository lookup and the Windows float workaround between both views.
local function lazygit(log)
    local root = Snacks.git.get_root()
    if not root then
        if not log then
            vim.notify("lazygit: not in a git repository", vim.log.levels.WARN)
        end
        return
    end
    if vim.fn.has("win32") == 1 then
        require("config.float_term").toggle({
            id = log and "lazygit-log" or "lazygit",
            cmd = log and { "lazygit", "log" } or { "lazygit" },
            cwd = root,
            env = { NVIM = "" },
        })
    else
        local open = log and Snacks.lazygit.log or Snacks.lazygit.open
        open({ cwd = root })
    end
end

-- Lazygit writes its generated theme here, including on first launch.
vim.fn.mkdir(vim.fn.stdpath("cache"), "p")

---@type snacks.Config
Snacks.setup({
    lazygit = { enabled = true },
    terminal = {
        enabled = true,
        win = {
            keys = { term_normal = false }, -- Pass Esc through to the terminal.
            wo = { wrap = true, sidescrolloff = 0 },
            -- termopen resets these window options after the terminal is created.
            on_buf = function(terminal)
                vim.api.nvim_create_autocmd("TermOpen", {
                    buffer = terminal.buf,
                    callback = function()
                        for _, win in ipairs(vim.fn.win_findbuf(terminal.buf)) do
                            vim.wo[win].wrap = true
                            vim.wo[win].sidescrolloff = 0
                        end
                    end,
                })
            end,
        },
    },
    image = {
        enabled = true,
        convert = { notify = true },
        -- PDFs use the Poppler preview, rather than ImageMagick's PDF decoder.
        formats = vim.tbl_filter(function(format)
            return format ~= "pdf"
        end, Snacks.config.image.formats),
    },
    picker = {
        enabled = true,
        preview = picker.preview_file,
        config = picker.configure_previews,
        actions = {
            sidekick_send = function(...)
                return require("sidekick.cli.picker.snacks").send(...)
            end,
        },
        win = {
            input = {
                keys = { ["<a-a>"] = { "sidekick_send", mode = { "n", "i" } } },
            },
        },
    },
})

-- Native packages register keys with Neovim; the upstream `keys` field is for lazy.nvim.
local keys = {
    -- Files and repositories.
    { "<leader>ff", Snacks.picker.files, desc = "Find files" },
    { "<leader>fg", Snacks.picker.grep, desc = "Live grep" },
    { "<leader>fb", Snacks.picker.buffers, desc = "Buffers" },
    { "<leader>fq", picker.ghq_repos, desc = "ghq repos" },
    { allocation.key("smart-files"), picker.smart_files, desc = "Find files (smart)" },
    { allocation.key("files"), Snacks.picker.files, desc = "Open file" },

    -- Git.
    { allocation.key("git"), lazygit, desc = "Lazygit" },
    {
        "<leader>gl",
        function()
            lazygit(true)
        end,
        desc = "Git log",
    },
    { "<leader>gf", Snacks.lazygit.log_file, desc = "Git log (file)" },

    -- Terminals. Use Ctrl+q to leave terminal mode before pressing a leader key.
    {
        "<leader>dc",
        function()
            Snacks.terminal.toggle({ "lazydocker" }, { win = { position = "float" } })
        end,
        desc = "Lazydocker",
    },
    {
        "<leader>tt",
        function()
            Snacks.terminal.toggle(nil, { win = { position = "bottom", height = 0.3 } })
        end,
        desc = "Toggle bottom terminal",
    },
    {
        "<leader>tf",
        function()
            require("config.float_term").toggle()
        end,
        desc = "Toggle floating terminal",
    },
}

for _, key in ipairs(keys) do
    vim.keymap.set(key.mode or "n", key[1], key[2], { desc = key.desc })
end
