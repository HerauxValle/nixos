local startup_insert = true  -- defined here, toggled in options.lua via vim.g.startup_insert

vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        -- uistate handles mode restore when save_mode is on
        if vim.g.save_mode then return end
        if vim.g.startup_insert and (vim.bo.buftype == "" or vim.bo.buftype == "acwrite") then
            vim.cmd("startinsert")
        end
    end,
})
