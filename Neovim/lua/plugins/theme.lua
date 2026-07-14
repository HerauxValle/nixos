local transparent = false  -- toggle transparency here
local active = "oxocarbon" -- change to any theme name below to switch

local function apply(scheme)
    vim.cmd("colorscheme " .. scheme)
    if transparent then
        vim.api.nvim_set_hl(0, "Normal",      { bg = "none" })
        vim.api.nvim_set_hl(0, "NormalNC",    { bg = "none" })
        vim.api.nvim_set_hl(0, "NormalFloat", { bg = "none" })
    end
end

return {
    { "nyoom-engineering/oxocarbon.nvim",      lazy = true },
    { "catppuccin/nvim", name = "catppuccin",  lazy = true },
    { "folke/tokyonight.nvim",                 lazy = true },
    { "rebelot/kanagawa.nvim",                 lazy = true },
    { "rose-pine/neovim", name = "rose-pine",  lazy = true },
    { "EdenEast/nightfox.nvim",                lazy = true },
    {
        "folke/tokyonight.nvim",
        name     = "theme-loader",
        lazy     = false,
        priority = 1000,
        config   = function()
            vim.o.background = "dark"
            apply(active)
        end,
    },
}
