local M = {}

function M.get_win_by_ft(ft)
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(w)
        if vim.bo[buf].filetype == ft then return w end
    end
end

function M.get_term_win()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(w)
        if vim.bo[buf].buftype == "terminal" then return w end
    end
end

return M
