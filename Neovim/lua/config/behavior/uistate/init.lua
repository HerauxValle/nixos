local save    = require("config.behavior.uistate.save")    -- also loads mode.lua
local restore = require("config.behavior.uistate.restore")

vim.api.nvim_create_autocmd("VimLeavePre", { callback = save })
vim.api.nvim_create_autocmd("VimEnter",    { callback = restore })
