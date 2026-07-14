return function(args)
    if #args < 1 then
        return vim.notify("Usage: Custom file remove <path>", vim.log.levels.WARN)
    end
    vim.fn.system("rm -r " .. args[1])
    vim.notify("Removed: " .. args[1])
end
