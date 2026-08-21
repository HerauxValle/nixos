local log  = require("config.behavior.uistate.log")

return function(state)
    -- Mode restore: runs after ToggleTerm (which fires BufEnter → startinsert).
    -- Find the main edit window and set mode there.
    local edit_win
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(w)
        local bt = vim.bo[buf].buftype
        if bt == "" or bt == "acwrite" then
            edit_win = w
            break
        end
    end
    if edit_win then vim.api.nvim_set_current_win(edit_win) end
    local mode = state.mode
    if mode == "insert" then
        log("RESTORE: entering insert mode")
        vim.cmd("startinsert")
    elseif mode == "normal" then
        log("RESTORE: enforcing normal mode")
        vim.cmd("stopinsert")
    else
        -- visual/terminal/other: fall back to startup_insert
        if vim.g.startup_insert then vim.cmd("startinsert") end
    end
end
