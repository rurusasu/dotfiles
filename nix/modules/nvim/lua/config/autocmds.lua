local M = {}

function M.setup()
    local group = vim.api.nvim_create_augroup("DotfilesEditing", { clear = true })

    -- コピーした範囲を短時間ハイライトして、操作結果を確認できるようにする。
    vim.api.nvim_create_autocmd("TextYankPost", {
        group = group,
        callback = function()
            vim.hl.on_yank({ higroup = "IncSearch", timeout = 150 })
        end,
    })

    -- 通常のファイルを開いたとき、前回編集していたカーソル位置に戻る。
    vim.api.nvim_create_autocmd("BufReadPost", {
        group = group,
        callback = function(args)
            local buf = args.buf
            if
                vim.bo[buf].buftype ~= ""
                or vim.bo[buf].filetype == "gitcommit"
                or vim.bo[buf].filetype == "gitrebase"
            then
                return
            end
            local win = vim.api.nvim_get_current_win()
            if vim.api.nvim_win_get_buf(win) ~= buf then
                return
            end
            local cursor = vim.api.nvim_win_get_cursor(win)
            if cursor[1] ~= 1 or cursor[2] ~= 0 then
                return
            end
            local mark = vim.api.nvim_buf_get_mark(buf, '"')
            if mark[1] == 0 or mark[1] > vim.api.nvim_buf_line_count(buf) then
                return
            end
            local line = vim.api.nvim_buf_get_lines(buf, mark[1] - 1, mark[1], false)[1]
            vim.api.nvim_win_set_cursor(win, { mark[1], math.min(mark[2], #line) })
            vim.cmd.normal({ "zv", bang = true })
        end,
    })

    -- フォーカス復帰とターミナル終了時に外部変更を確認する。
    -- checktime は未保存の編集を自動で上書きしない。
    vim.api.nvim_create_autocmd({ "FocusGained", "TermClose" }, {
        group = group,
        callback = function()
            if vim.fn.getcmdwintype() == "" and vim.fn.mode():sub(1, 1) ~= "c" then
                vim.cmd.checktime()
            end
        end,
    })
end

return M
