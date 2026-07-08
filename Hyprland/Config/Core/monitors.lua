-- ################
-- ### MONITORS ###
-- ################

-- 1. Samsung LC27G7xT (Main 2K 240Hz) - Shifted down to allow Dell to be "Higher"
hl.monitor({
    output   = "desc:Samsung Electric Company LC27G7xT H4ZT200305",
    mode     = "2560x1440@239.96",
    position = "0x360",
    scale    = 1,
})

-- 2. Dell P2319H (Secondary FHD 60Hz) - At the top-right
hl.monitor({
    output   = "desc:Dell Inc. DELL P2319H 38K4123",
    mode     = "1920x1080@60",
    position = "2560x0",
    scale    = 1,
})

-- 3. Portability Fallback
hl.monitor({
    output   = "",
    mode     = "highres",
    position = "auto",
    scale    = 1,
})
