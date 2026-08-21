return function(args)
    if #args < 2 then
        return vim.notify("Usage: Custom file copy <src> <dst>", vim.log.levels.WARN)
    end
    vim.fn.system("cp -r " .. args[1] .. " " .. args[2])
    vim.notify("Copied: " .. args[1] .. " → " .. args[2])
end
