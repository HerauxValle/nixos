return function(args)
    local name = args[1]
    if not name then
        return vim.notify("Usage: Custom scheme default <name>", vim.log.levels.WARN)
    end
    local theme_file = vim.fn.stdpath("config") .. "/lua/plugins/theme.lua"
    local content = table.concat(vim.fn.readfile(theme_file), "\n")
    content = content:gsub('local active = "[^"]*"', 'local active = "' .. name .. '"')
    vim.fn.writefile(vim.split(content, "\n"), theme_file)
    vim.notify("Default set to: " .. name .. " (restart to apply)")
end
