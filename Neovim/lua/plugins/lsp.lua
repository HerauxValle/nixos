-- To add a new LSP: add its mason name to the servers table.
-- Find names at: https://mason-registry.dev/registry/list
local servers = {
    -- Systems
    "rust_analyzer",
    "clangd",        -- C, C++
    "gopls",
    -- Scripting
    "pyright",
    "bashls",        -- bash/sh (fish has no LSP)
    -- Web
    "html",
    "cssls",
    "ts_ls",         -- TypeScript & JavaScript
    -- Markup / data
    "marksman",      -- Markdown
    "jsonls",
    "yamlls",
    "sqls",          -- SQL
    "qmlls",         -- QML
    -- Config / scripting
    "lua_ls",
}

return {
    {
        "williamboman/mason.nvim",
        build = ":MasonUpdate",
        opts  = {},
    },
    {
        "williamboman/mason-lspconfig.nvim",
        dependencies = { "williamboman/mason.nvim" },
        opts = {
            ensure_installed    = servers,
            automatic_installation = true,
        },
    },
    {
        "neovim/nvim-lspconfig",
        dependencies = { "williamboman/mason-lspconfig.nvim" },
        config = function()
            vim.lsp.enable(servers)

            -- LSP keymaps (only active when an LSP is attached)
            vim.api.nvim_create_autocmd("LspAttach", {
                callback = function(ev)
                    local map = function(lhs, rhs, desc)
                        vim.keymap.set("n", lhs, rhs, { buffer = ev.buf, desc = desc })
                    end
                    map("gd",        vim.lsp.buf.definition,    "Go to definition")
                    map("gD",        vim.lsp.buf.declaration,   "Go to declaration")
                    map("gr",        vim.lsp.buf.references,    "References")
                    map("K",         vim.lsp.buf.hover,         "Hover docs")
                    map("<leader>rn", vim.lsp.buf.rename,       "Rename")
                    map("<leader>a", vim.lsp.buf.code_action,   "Code action")
                    map("<leader>d", vim.diagnostic.open_float, "Diagnostics")
                    map("[d",        vim.diagnostic.goto_prev,  "Prev diagnostic")
                    map("]d",        vim.diagnostic.goto_next,  "Next diagnostic")

                    -- Show signature help while typing
                    vim.api.nvim_create_autocmd("CursorHoldI", {
                        buffer = ev.buf,
                        callback = function() vim.lsp.buf.signature_help() end,
                    })
                end,
            })
        end,
    },
}
