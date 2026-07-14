return function(args)
    local ms = tonumber(args[1])
    if not ms then
        vim.notify("Autosave delay: " .. vim.g.autosave_delay .. "ms")
        return
    end
    vim.g.autosave_delay = ms
    vim.notify("Autosave delay set to " .. ms .. "ms")
end
