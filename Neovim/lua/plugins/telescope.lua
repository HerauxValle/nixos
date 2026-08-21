return {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
        { "<leader>ff", "<cmd>Telescope find_files<cr>",  desc = "Find files" },
        { "<leader>fg", "<cmd>Telescope live_grep<cr>",   desc = "Live grep" },
        { "<leader>fb", "<cmd>Telescope buffers<cr>",     desc = "Buffers" },
        { "<leader>fr", "<cmd>Telescope oldfiles<cr>",    desc = "Recent files" },
        { "<leader>fc", "<cmd>Telescope colorscheme<cr>", desc = "Theme picker" },
    },
    opts = {
        defaults = {
            layout_strategy = "horizontal",
            sorting_strategy = "ascending",
            layout_config = {
                prompt_position = "top",
            },
        },
    },
}
