local log        = require("config.behavior.uistate.log")
local wins       = require("config.behavior.uistate.wins")
local get_mode   = require("config.behavior.uistate.mode")
local state_file = vim.fn.stdpath("state") .. "/uistate.json"

return function()
    local state = {}

    if vim.g.save_ui_state then
        state.explorer = wins.get_win_by_ft("neo-tree") ~= nil
        state.terminal = wins.get_term_win() ~= nil
        state.undotree = wins.get_win_by_ft("undotree") ~= nil
    end

    if vim.g.save_widget_sizes then
        local ew = wins.get_win_by_ft("neo-tree")
        local tw = wins.get_term_win()
        local uw = wins.get_win_by_ft("undotree")
        state.explorer_width  = ew and vim.api.nvim_win_get_width(ew)  or nil
        state.terminal_height = tw and vim.api.nvim_win_get_height(tw) or nil
        state.undotree_width  = uw and vim.api.nvim_win_get_width(uw)  or nil
    end

    if vim.g.save_mode then
        state.mode = get_mode()
    end

    log("SAVE: explorer=" .. tostring(state.explorer)
        .. " undotree=" .. tostring(state.undotree)
        .. " terminal=" .. tostring(state.terminal)
        .. " mode=" .. tostring(state.mode))

    vim.fn.writefile({ vim.json.encode(state) }, state_file)
end
