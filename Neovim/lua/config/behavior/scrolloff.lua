vim.api.nvim_create_autocmd({ "CursorMovedI", "CursorMoved" }, {
    callback = function()
        local offset = vim.o.scrolloff
        local win_height = vim.api.nvim_win_get_height(0)
        local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
        local first_visible = vim.fn.line("w0")
        if cursor_line - first_visible < offset then
            vim.fn.winrestview({ topline = math.max(1, cursor_line - offset) })
        elseif (first_visible + win_height - 1) - cursor_line < offset then
            vim.fn.winrestview({ topline = cursor_line - win_height + offset + 1 })
        end
    end,
})
