local log        = require("config.behavior.uistate.log")
local wins       = require("config.behavior.uistate.wins")
local panels     = require("config.behavior.uistate.panels")
local modeapply  = require("config.behavior.uistate.modeapply")
local state_file = vim.fn.stdpath("state") .. "/uistate.json"

return function()
    if vim.fn.filereadable(state_file) == 0 then log("RESTORE: no state file"); return end
    local ok, state = pcall(vim.json.decode, vim.fn.readfile(state_file)[1])
    if not ok then log("RESTORE: json decode failed"); return end

    log("RESTORE: explorer=" .. tostring(state.explorer)
        .. " undotree=" .. tostring(state.undotree)
        .. " terminal=" .. tostring(state.terminal)
        .. " mode=" .. tostring(state.mode))

    -- Explorer is idempotent (show/close don't toggle), open early
    vim.defer_fn(function()
        if not vim.g.save_ui_state then return end
        if state.explorer then pcall(vim.cmd, "Neotree show")
        else                    pcall(vim.cmd, "Neotree close") end
    end, 50)

    -- After auto-session restores, reconcile toggle-based panels then mode
    vim.defer_fn(function()
        if vim.g.save_ui_state  then panels(state)    end
        if vim.g.save_mode      then modeapply(state) end
    end, 600)

    -- Restore panel sizes after everything is open
    vim.defer_fn(function()
        if not vim.g.save_widget_sizes then return end
        local ew = wins.get_win_by_ft("neo-tree")
        local tw = wins.get_term_win()
        local uw = wins.get_win_by_ft("undotree")
        log("SIZES: ew=" .. tostring(ew) .. " tw=" .. tostring(tw) .. " uw=" .. tostring(uw))
        if ew and state.explorer_width  then vim.api.nvim_win_set_width(ew,  state.explorer_width)  end
        if tw and state.terminal_height then vim.api.nvim_win_set_height(tw, state.terminal_height) end
        if uw and state.undotree_width  then vim.api.nvim_win_set_width(uw,  state.undotree_width)  end
    end, 800)
end
