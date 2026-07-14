local log_file = vim.fn.stdpath("state") .. "/uistate.log"

return function(msg)
    local f = io.open(log_file, "a")
    if f then f:write(os.date("%H:%M:%S") .. " " .. msg .. "\n"); f:close() end
end
