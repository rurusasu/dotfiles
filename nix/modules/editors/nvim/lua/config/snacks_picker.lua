local Snacks = require("snacks")
local M = {}

---@param ctx snacks.picker.preview.ctx
function M.preview_file(ctx)
    local preview = require("snacks.picker.preview")
    local file = Snacks.picker.util.path(ctx.item) or (ctx.item and ctx.item.path)
    if not file or not file:match("%.pdf$") then
        return preview.file(ctx)
    end
    if vim.fn.executable("pdftoppm") == 0 then
        vim.notify("PDF preview requires Poppler (pdftoppm). See docs/chezmoi/neovim.md.", vim.log.levels.WARN)
        return false
    end
    local tmp = vim.fn.tempname()
    local result = vim.system({ "pdftoppm", "-png", "-r", "150", "-singlefile", file, tmp }, { text = true })
        :wait(10000)
    if result.code ~= 0 then
        vim.fn.delete(tmp .. ".png")
        vim.notify("PDF conversion failed: " .. (result.stderr or tostring(result.code)), vim.log.levels.WARN)
        return false
    end
    tmp = tmp .. ".png"
    return preview.image(vim.tbl_extend("force", ctx, {
        item = vim.tbl_extend("force", ctx.item, { file = tmp, _path = tmp }),
    }))
end

-- Preserve dedicated previews in mixed-source pickers, such as Git history.
function M.configure_previews(opts)
    if not opts.multi or opts.preview ~= M.preview_file then
        return
    end
    opts.preview = nil
    for i, source in ipairs(opts.multi) do
        source = type(source) == "string" and { source = source } or source
        local preset = opts.sources[source.source] or {}
        local preview = source.preview or preset.preview
        if not preview or preview == "file" then
            opts.multi[i] = vim.tbl_extend("force", source, { preview = M.preview_file })
        end
    end
end

function M.ghq_repos()
    if vim.fn.executable("ghq") == 0 then
        vim.notify("ghq not found", vim.log.levels.WARN)
        return
    end
    Snacks.picker.pick("proc", {
        cmd = "ghq",
        args = { "list", "--full-path" },
        title = "ghq repos",
        transform = function(item)
            item.file = item.text
            return item
        end,
        confirm = function(picker, item)
            picker:close()
            if item and item.file then
                vim.cmd.cd(item.file)
            end
        end,
    })
end

function M.smart_files()
    local sources = require("snacks.picker.config.sources")
    local files = Snacks.git.get_root() == nil and sources.files
        or vim.tbl_deep_extend("force", sources.git_files, {
            untracked = true,
            cwd = vim.uv.cwd(),
        })
    Snacks.picker({
        multi = { "buffers", "recent", files },
        format = "file",
        matcher = { frecency = true, sort_empty = true },
        filter = { cwd = true },
        transform = "unique_file",
    })
end

return M
