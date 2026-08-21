-- Dispatcher for :Custom <group> <subcommand> [args...]
-- To add a new group: create lua/commands/<group>/<subcommand>.lua


vim.api.nvim_create_user_command("Custom", function(opts)
    local args = vim.split(opts.args, " ", { trimempty = true })
    local group = table.remove(args, 1)
    local sub   = table.remove(args, 1)


    if not group then
        return vim.notify("Usage: Custom <group> <subcommand> [args...]", vim.log.levels.WARN)
    end

    -- No subcommand — try group-level init fallback
    if not sub then
        local ok, fn = pcall(require, "commands." .. group .. ".init")
        if ok then return fn(args) end
        return vim.notify("Usage: Custom " .. group .. " <subcommand>", vim.log.levels.WARN)
    end

    local ok, fn = pcall(require, "commands." .. group .. "." .. sub)
    if not ok then
        return vim.notify("Unknown command: Custom " .. group .. " " .. sub, vim.log.levels.ERROR)
    end

    fn(args)
end, {
    nargs = "+",
    desc  = "Custom command dispatcher",
})
