vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        if vim.g.save_ui_state then return end
        if vim.g.autostart_terminal then
            vim.schedule(function()
                vim.cmd("ToggleTerm direction=horizontal")
            end)
        end
    end,
})
