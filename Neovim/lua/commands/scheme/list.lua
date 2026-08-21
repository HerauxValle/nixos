local themes = {
    "oxocarbon",
    "catppuccin",
    "tokyonight",
    "kanagawa",
    "rose-pine",
    "nightfox",
    "habamax",
    "retrobox",
}

return function(_args)
    print("Available themes:")
    for _, t in ipairs(themes) do
        print("  " .. t)
    end
end
