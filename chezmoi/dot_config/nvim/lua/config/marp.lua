local M = {}

local state = {
    job = nil,
    root = nil,
    stopping = false,
    url = "http://localhost:8080/",
}

local function current_start_path()
    local file = vim.api.nvim_buf_get_name(0)
    if file ~= "" then
        return vim.fs.dirname(file)
    end
    return vim.uv.cwd()
end

local function project_root()
    return vim.fs.root(current_start_path(), { "package.json", ".git" }) or vim.uv.cwd()
end

local function has_slide_preview_script(root)
    local package_json = root .. "/package.json"
    if vim.fn.filereadable(package_json) == 0 then
        return false
    end

    local ok, parsed = pcall(vim.json.decode, table.concat(vim.fn.readfile(package_json), "\n"))
    return ok and parsed and parsed.scripts and parsed.scripts["slide:preview"] ~= nil
end

local function open_url(url)
    if vim.ui and vim.ui.open then
        vim.ui.open(url)
        return
    end

    if vim.fn.has("win32") == 1 then
        vim.fn.jobstart({ "cmd.exe", "/c", "start", "", url }, { detach = true })
    elseif vim.fn.has("mac") == 1 then
        vim.fn.jobstart({ "open", url }, { detach = true })
    else
        vim.fn.jobstart({ "xdg-open", url }, { detach = true })
    end
end

local function open_when_ready(line)
    local url = line:match("(https?://localhost:%d+/?)")
    if not url then
        return false
    end
    state.url = url
    open_url(url)
    return true
end

function M.start()
    if state.job and state.job > 0 then
        open_url(state.url)
        vim.notify("Marp preview is already running: " .. state.url, vim.log.levels.INFO)
        return
    end

    local root = project_root()
    if not has_slide_preview_script(root) then
        vim.notify("No slide:preview script found in " .. root, vim.log.levels.WARN)
        return
    end

    state.root = root
    state.url = "http://localhost:8080/"
    local opened = false
    local function on_output(_, data)
        for _, line in ipairs(data or {}) do
            if line ~= "" then
                opened = open_when_ready(line) or opened
            end
        end
    end

    state.job = vim.fn.jobstart({ "bun", "run", "slide:preview" }, {
        cwd = root,
        stdout_buffered = false,
        stderr_buffered = false,
        on_stdout = on_output,
        on_stderr = on_output,
        on_exit = function(_, code)
            local stopping = state.stopping
            state.job = nil
            state.stopping = false
            if code ~= 0 and not stopping then
                vim.notify("Marp preview exited with code " .. code, vim.log.levels.WARN)
            end
        end,
    })

    if state.job <= 0 then
        state.job = nil
        vim.notify("Failed to start Marp preview", vim.log.levels.ERROR)
        return
    end

    vim.defer_fn(function()
        if state.job and not opened then
            open_url(state.url)
        end
    end, 1200)
end

function M.stop()
    if not state.job then
        vim.notify("Marp preview is not running", vim.log.levels.INFO)
        return
    end
    state.stopping = true
    vim.fn.jobstop(state.job)
end

function M.toggle()
    if state.job then
        M.stop()
    else
        M.start()
    end
end

function M.status()
    if state.job then
        vim.notify("Marp preview running: " .. state.url .. " (" .. state.root .. ")", vim.log.levels.INFO)
    else
        vim.notify("Marp preview is not running", vim.log.levels.INFO)
    end
end

function M.setup()
    vim.api.nvim_create_user_command("MarpPreview", M.start, { desc = "Start Marp preview server" })
    vim.api.nvim_create_user_command("MarpStop", M.stop, { desc = "Stop Marp preview server" })
    vim.api.nvim_create_user_command("MarpToggle", M.toggle, { desc = "Toggle Marp preview server" })
    vim.api.nvim_create_user_command("MarpStatus", M.status, { desc = "Show Marp preview server status" })
end

return M
