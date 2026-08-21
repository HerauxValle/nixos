return function(args)
    local name = args[1]
    if not name then
        return vim.notify("Usage: Custom scheme load <name>", vim.log.levels.WARN)
    end
    vim.cmd("colorscheme " .. name)
    vim.notify("Loaded: " .. name)
end
