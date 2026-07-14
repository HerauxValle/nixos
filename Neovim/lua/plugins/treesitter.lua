return {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    lazy = false,
    config = function()
        require("nvim-treesitter").setup({
            ensure_installed = {
                "lua", "vim", "vimdoc",
                "rust", "c", "cpp",
                "python", "go",
                "bash",
                "html", "css", "javascript", "typescript",
                "json", "yaml", "toml",
                "markdown", "sql",
            },
            auto_install  = true,
            highlight     = { enable = true },
            indent        = { enable = true },
        })
    end,
}
