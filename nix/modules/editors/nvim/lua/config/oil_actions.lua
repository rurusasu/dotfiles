-- Keep file mutations in Oil's edit/save flow, including trash and LSP notifications.
local M = {}

local function sidebar()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.w[win].dotfiles_oil_sidebar and vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "oil" then
            return win
        end
    end
end

function M.toggle_sidebar()
    local win = sidebar()
    if win then
        vim.api.nvim_win_close(win, false)
        return
    end
    local editor = vim.api.nvim_get_current_win()
    vim.cmd("topleft 32vsplit")
    vim.w.dotfiles_oil_sidebar = true
    vim.w.dotfiles_oil_editor = editor
    require("oil").open()
end

function M.select()
    local source = vim.api.nvim_get_current_win()
    local target = vim.w.dotfiles_oil_editor
    if not vim.w.dotfiles_oil_sidebar or not target or not vim.api.nvim_win_is_valid(target) then
        require("oil").select()
        return
    end
    require("oil").select({
        handle_buffer_callback = function(buf)
            -- Oil invokes this callback for directory buffers before they are loaded.
            local is_directory = vim.bo[buf].filetype == "oil" or vim.endswith(vim.api.nvim_buf_get_name(buf), "/")
            local win = is_directory and source or target
            if vim.api.nvim_win_is_valid(win) then
                vim.api.nvim_win_set_buf(win, buf)
                vim.api.nvim_set_current_win(win)
            end
        end,
    })
end

function M.close()
    if vim.w.dotfiles_oil_sidebar then
        vim.api.nvim_win_close(0, false)
    else
        require("oil").close()
    end
end

function M.resize(amount)
    vim.api.nvim_win_call(sidebar() or vim.api.nvim_get_current_win(), function()
        vim.cmd("vertical resize " .. (amount > 0 and "+" or "") .. amount)
    end)
end

local function context(require_entry)
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].filetype ~= "oil" or not vim.bo[buf].modifiable then
        return
    end
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local entry = require("oil").get_cursor_entry()
    if require_entry and (not entry or entry.id == 0 or entry.name == "..") then
        return
    end
    return { buf = buf, row = row, entry = entry, line = vim.api.nvim_get_current_line() }
end

local function unchanged(ctx)
    return vim.api.nvim_buf_is_valid(ctx.buf)
        and vim.bo[ctx.buf].modifiable
        and vim.api.nvim_buf_get_lines(ctx.buf, ctx.row - 1, ctx.row, false)[1] == ctx.line
end

local function name_input(opts, callback)
    vim.ui.input(opts, function(name)
        if not name or name == "" then
            return
        end
        if name == "." or name == ".." or name:find("[/\\\r\n]") then
            vim.notify("Enter a single file or directory name", vim.log.levels.WARN)
            return
        end
        callback(name)
    end)
end

function M.add(directory)
    local ctx = context(false)
    if not ctx then
        return
    end
    name_input({ prompt = directory and "New directory: " or "New file: " }, function(name)
        if not unchanged(ctx) then
            return
        end
        vim.api.nvim_buf_call(ctx.buf, function()
            vim.api.nvim_buf_set_lines(ctx.buf, ctx.row, ctx.row, false, { name .. (directory and "/" or "") })
            require("oil").save({ confirm = true })
        end)
    end)
end

function M.delete()
    local ctx = context(true)
    if not ctx then
        return
    end
    vim.api.nvim_buf_set_lines(ctx.buf, ctx.row - 1, ctx.row, false, {})
    require("oil").save({ confirm = true })
end

function M.rename()
    local ctx = context(true)
    if not ctx then
        return
    end
    name_input({ prompt = "Rename: ", default = ctx.entry.parsed_name or ctx.entry.name }, function(name)
        if not unchanged(ctx) then
            return
        end
        vim.api.nvim_buf_call(ctx.buf, function()
            -- Use Oil's column parser to retain the entry ID, icon, and symlink target.
            local adapter = require("oil.util").get_adapter(ctx.buf)
            local columns = require("oil.columns").get_supported_columns(adapter)
            local parsed = require("oil.mutator.parser").parse_line(adapter, ctx.line, columns)
            if not parsed or not parsed.ranges.name then
                vim.notify("Save the new Oil entry before renaming it", vim.log.levels.WARN)
                return
            end
            local range = parsed.ranges.name
            -- Oil ranges are zero-based and inclusive; Neovim's end column is exclusive.
            local suffix = ctx.line:sub(range[1] + 1, range[2] + 1):match("/%s*$") and "/" or ""
            vim.api.nvim_buf_set_text(ctx.buf, ctx.row - 1, range[1], ctx.row - 1, range[2] + 1, { name .. suffix })
            require("oil").save({ confirm = true })
        end)
    end)
end

function M.move()
    local ctx = context(true)
    local oil = require("oil")
    local current_dir = oil.get_current_dir()
    if not ctx or not current_dir then
        return
    end
    vim.ui.input({ prompt = "Move to directory: ", default = current_dir, completion = "dir" }, function(destination)
        if not destination or destination == "" or not unchanged(ctx) then
            return
        end
        if not vim.startswith(destination, "/") and not destination:match("^%a:[/\\]") then
            destination = vim.fs.joinpath(current_dir, destination)
        end
        destination = vim.fs.normalize(destination)
        if vim.fn.isdirectory(destination) ~= 1 then
            vim.notify("Destination directory does not exist", vim.log.levels.WARN)
            return
        end
        if destination:gsub("[/\\]+$", "") == vim.fs.normalize(current_dir):gsub("[/\\]+$", "") then
            return
        end
        oil.open(destination, {}, function()
            local destination_buf = vim.api.nvim_get_current_buf()
            local function stage_move(load_err)
                if load_err then
                    vim.notify("Could not load move destination: " .. tostring(load_err), vim.log.levels.ERROR)
                    return
                end
                if not unchanged(ctx) or vim.api.nvim_get_current_buf() ~= destination_buf then
                    return
                end
                if destination_buf == ctx.buf or vim.bo[destination_buf].filetype ~= "oil" then
                    return
                end
                if not vim.bo[destination_buf].modifiable then
                    vim.notify("Destination directory is read-only", vim.log.levels.WARN)
                    return
                end
                local snapshots = {}
                for _, buf in ipairs({ ctx.buf, destination_buf }) do
                    snapshots[#snapshots + 1] = {
                        buf = buf,
                        lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
                        modified = vim.bo[buf].modified,
                    }
                end
                -- Moving the original ID between Oil buffers makes this a move, not a copy.
                -- Append first so an unwritable destination can never stage source deletion.
                local ok, err = pcall(function()
                    vim.api.nvim_buf_set_lines(destination_buf, -1, -1, false, { ctx.line })
                    vim.api.nvim_buf_set_lines(ctx.buf, ctx.row - 1, ctx.row, false, {})
                end)
                if not ok then
                    for _, snapshot in ipairs(snapshots) do
                        local restored, restore_err = pcall(function()
                            local was_modifiable = vim.bo[snapshot.buf].modifiable
                            vim.bo[snapshot.buf].modifiable = true
                            local written, write_err = pcall(vim.api.nvim_buf_call, snapshot.buf, function()
                                pcall(vim.cmd, "undojoin")
                                vim.api.nvim_buf_set_lines(snapshot.buf, 0, -1, false, snapshot.lines)
                            end)
                            vim.bo[snapshot.buf].modifiable = was_modifiable
                            if not written then
                                error(write_err)
                            end
                            vim.bo[snapshot.buf].modified = snapshot.modified
                        end)
                        if not restored then
                            err = tostring(err) .. "; could not restore Oil buffer: " .. tostring(restore_err)
                        end
                    end
                    vim.notify("Move was not staged: " .. tostring(err), vim.log.levels.ERROR)
                    return
                end
                oil.save({ confirm = true })
            end
            if vim.b[destination_buf].oil_rendering then
                -- oil.open treats cached oil_ready buffers as loaded even during a refresh.
                require("oil.view").render_buffer_async(destination_buf, { refetch = false }, stage_move)
            else
                stage_move()
            end
        end)
    end)
end

return M
