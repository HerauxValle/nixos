vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        if vim.g.save_ui_state then return end
        if vim.g.autostart_explorer and vim.fn.argc() == 0 then
            vim.schedule(function()
                vim.cmd("Neotree show")
            end)
        end
    end,
})
