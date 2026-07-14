return {
    "akinsho/bufferline.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    lazy = false,
    keys = {
        { "<Tab>",   "<cmd>BufferLineCycleNext<cr>", desc = "Next buffer" },
        { "<S-Tab>", "<cmd>BufferLineCyclePrev<cr>", desc = "Prev buffer" },
        { "<leader>x", function()
            local bufs = vim.fn.getbufinfo({ buflisted = 1 })
            if #bufs <= 1 then
                vim.cmd("enew | bdelete #")
            else
                vim.cmd("bprevious | bdelete #")
            end
        end, desc = "Close buffer" },
    },
    opts = {
        options = {
            diagnostics = "nvim_lsp",
            offsets = {
                {
                    filetype   = "neo-tree",
                    text       = "Explorer",
                    highlight  = "Directory",
                    separator  = true,
                }
            },
        },
    },
}
