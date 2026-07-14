return {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    keys = {
        { "<leader>f", function() require("conform").format({ async = true }) end, desc = "Format file" },
    },
    opts = {
        -- To add a formatter: add it to the list for that filetype.
        -- Install formatters via Mason (:Mason → Formatter tab)
        formatters_by_ft = {
            rust       = { "rustfmt" },
            c          = { "clang_format" },
            cpp        = { "clang_format" },
            python     = { "black" },
            go         = { "gofmt" },
            lua        = { "stylua" },
            javascript = { "prettier" },
            typescript = { "prettier" },
            html       = { "prettier" },
            css        = { "prettier" },
            json       = { "prettier" },
            yaml       = { "prettier" },
            markdown   = { "prettier" },
            sh         = { "shfmt" },
            sql        = { "sqlfmt" },
        },
        format_on_save = {
            timeout_ms = 500,
            lsp_fallback = true,
        },
    },
}
