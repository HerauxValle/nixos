return {
    "echasnovski/mini.nvim",
    lazy = false,
    config = function()
        require("mini.pairs").setup()       -- auto close brackets/quotes
        require("mini.comment").setup()     -- gcc to toggle comment
        require("mini.surround").setup()    -- sa/sd/sr to add/delete/replace surrounds
        require("mini.indentscope").setup() -- animated indent guides
        require("mini.cursorword").setup()  -- highlight word under cursor
    end,
}
