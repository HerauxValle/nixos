return {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-tree/nvim-web-devicons",
        "MunifTanjim/nui.nvim",
    },
    keys = {
        { "<leader>e", "<cmd>Neotree toggle<cr>", desc = "Toggle explorer" },
        { "<leader>o", "<cmd>Neotree focus<cr>",  desc = "Focus explorer" },
    },
    lazy = false,
    opts = {
        window = {
            position = "left",
            width    = 30,
        },
        filesystem = {
            follow_current_file  = { enabled = true },
            hijack_netrw_behavior = "open_current",
            use_libuv_file_watcher = true,
        },
    },
    config = function(_, opts)
        require("neo-tree").setup(opts)
    end,
}
