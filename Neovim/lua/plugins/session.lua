local enabled = true  -- toggle session save/restore here

return {
    "rmagatti/auto-session",
    lazy = false,
    opts = {
        auto_save    = enabled,
        auto_restore = enabled,
        pre_save_cmds    = { "Neotree close" },
        pre_restore_cmds = { "Neotree close" },
    },
}
