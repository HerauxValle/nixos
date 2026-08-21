local log = require("config.behavior.uistate.log")

local last_mode = "normal"

vim.api.nvim_create_autocmd("InsertEnter", {
    callback = function()
        last_mode = "insert"
        log("InsertEnter from: " .. debug.traceback("", 2):gsub("\n", " | "))
    end
})
vim.api.nvim_create_autocmd("InsertLeave", { callback = function() last_mode = "normal" end })

return function() return last_mode end
