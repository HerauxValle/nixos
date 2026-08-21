-- options set in config/options.lua (autosave_enabled, autosave_delay)
local timer = nil

local function schedule_save()
    if not vim.g.autosave_enabled then return end
    -- restart the debounce timer on every text change
    if timer then vim.fn.timer_stop(timer) end
    timer = vim.fn.timer_start(vim.g.autosave_delay, function()
        local buf = vim.api.nvim_get_current_buf()
        -- only save named, unmodified-type buffers (skip terminals, prompts, unsaved scratch)
        if vim.bo[buf].modified and vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then
            vim.cmd("silent! write")
        end
    end)
end

vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    callback = schedule_save,
})
