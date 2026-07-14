return {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    lazy = false,
    opts = {
        options = {
            theme                = "auto",
            globalstatus         = true,
            section_separators   = { left = "", right = "" },
            component_separators = { left = "│", right = "│" },
        },
        -- Bottom statusline
        sections = {
            lualine_a = { "mode" },
            lualine_b = { "branch", "diff", "diagnostics" },
            lualine_c = { { "filename", path = 1 } },
            lualine_x = { "filetype" },
            lualine_y = { "progress" },
            lualine_z = { "location" },
        },
        -- Top winbar: filename left, time right (hidden for neo-tree)
        winbar = {
            lualine_c = {
                {
                    "filename",
                    path = 1,
                    cond = function()
                        return vim.bo.filetype ~= "neo-tree"
                    end,
                },
            },
            lualine_x = {
                {
                    function() return os.date("%H:%M:%S | %d.%m.%Y") end,
                    cond = function()
                        return vim.bo.filetype ~= "neo-tree"
                    end,
                },
            },
        },
        inactive_winbar = {
            lualine_c = {
                {
                    "filename",
                    path = 1,
                    cond = function()
                        return vim.bo.filetype ~= "neo-tree"
                    end,
                },
            },
        },
    },
}
