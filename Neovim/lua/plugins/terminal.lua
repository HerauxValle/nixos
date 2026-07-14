return {
    "akinsho/toggleterm.nvim",
    lazy = false,
    keys = {
        { "<C-t>",     "<cmd>ToggleTerm direction=horizontal<cr>", desc = "Toggle terminal" },
        { "<leader>gg", function()
            require("toggleterm.terminal").Terminal:new({
                cmd = "lazygit",
                direction = "float",
                float_opts = { border = "rounded" },
                hidden = true,
            }):toggle()
        end, desc = "Lazygit" },
        { "<leader>gd", function()
            require("toggleterm.terminal").Terminal:new({
                cmd = "lazydocker",
                direction = "float",
                float_opts = { border = "rounded" },
                hidden = true,
            }):toggle()
        end, desc = "Lazydocker" },
    },
    opts = {
        size = 15,
        direction = "horizontal",
        shade_terminals = true,
    },
}
