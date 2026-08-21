return function(args)
    local val = args[1]
    if val == "true" then
        vim.g.autosave_enabled = true
        vim.notify("Autosave enabled")
    elseif val == "false" then
        vim.g.autosave_enabled = false
        vim.notify("Autosave disabled")
    else
        vim.notify("Autosave is " .. (vim.g.autosave_enabled and "enabled" or "disabled"))
    end
end
