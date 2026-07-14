-- Overwrite directories
vim.env.XDG_DATA_HOME   = vim.fn.expand("~/.impure/neovim/data")
vim.env.XDG_STATE_HOME  = vim.fn.expand("~/.impure/neovim/state")
vim.env.XDG_CACHE_HOME  = vim.fn.expand("~/.impure/neovim/cache")

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

-- Optional XDG handles it
-- local lazypath = vim.fn.expand("~/.impure/neovim/lazy.nvim")

-- if not vim.loop.fs_stat(lazypath) then
--     vim.fn.system({
--         "git", "clone", "--filter=blob:none",
--         "https://github.com/folke/lazy.nvim.git",
--         "--branch=stable",
--         lazypath,
--     })
-- end

if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable",
        lazypath,
    })
end

vim.opt.rtp:prepend(lazypath)

-- require("lazy").setup("plugins", {
--     change_detection = { notify = false },
-- })

require("lazy").setup("plugins", {
    root = vim.fn.expand("~/.impure/neovim/plugins"),
    change_detection = { notify = false },
})
