return function(args)
    if #args < 2 then
        return vim.notify("Usage: Custom file move <src> <dst>", vim.log.levels.WARN)
    end
    vim.fn.system("mv " .. args[1] .. " " .. args[2])
    vim.notify("Moved: " .. args[1] .. " → " .. args[2])
end
