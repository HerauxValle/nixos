vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        if vim.g.save_ui_state then return end
        if vim.g.autostart_undotree then
            vim.schedule(function()
                vim.cmd("UndotreeToggle")
            end)
        end
    end,
})
