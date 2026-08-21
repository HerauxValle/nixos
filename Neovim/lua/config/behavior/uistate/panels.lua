local log  = require("config.behavior.uistate.log")
local wins = require("config.behavior.uistate.wins")

return function(state)
    -- Log all window filetypes for debugging
    local fts = {}
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(w)
        table.insert(fts, vim.bo[buf].filetype)
    end
    log("WINS at 600ms: " .. table.concat(fts, ", "))

    -- Undotree: toggle only if current state differs from saved state
    local undotree_open = wins.get_win_by_ft("undotree") ~= nil
    log("undotree_open=" .. tostring(undotree_open) .. " state.undotree=" .. tostring(state.undotree))
    if state.undotree and not undotree_open then
        log("RESTORE: opening undotree")
        pcall(vim.cmd, "UndotreeToggle")
    elseif not state.undotree and undotree_open then
        log("RESTORE: closing undotree")
        pcall(vim.cmd, "UndotreeToggle")
    end

    -- Terminal: toggle only if current state differs from saved state
    local term_open = wins.get_term_win() ~= nil
    if state.terminal and not term_open then
        log("RESTORE: opening terminal")
        pcall(vim.cmd, "ToggleTerm direction=horizontal")
    elseif not state.terminal and term_open then
        log("RESTORE: closing terminal")
        pcall(vim.cmd, "ToggleTerm direction=horizontal")
    end
end
