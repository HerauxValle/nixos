# &desc: "mcfunction enforcing the agreed Vanilla Refresh 14-feature whitelist, packaged into a companion datapack by plugins.nix's vanillaRefreshOverridesDatapack."
# Force-enforces the agreed 14-feature whitelist every time the world
# loads, overwriting whatever Vanilla Refresh's own defaults or any
# player toggling set. Unconditional "set value" (no "unless" guard),
# so it wins regardless of load order relative to vanilla_refresh:load.

# --- ENABLED (the 14 agreed features) ---
data modify storage vanilla_refresh_config:config config.daycounter set value 1
data modify storage vanilla_refresh_config:config config.craftsound set value 1
data modify storage vanilla_refresh_config:config config.jukebox set value 1
data modify storage vanilla_refresh_config:config config.armorstand set value 1
data modify storage vanilla_refresh_config:config config.witherhead set value 1
data modify storage vanilla_refresh_config:config config.banner set value 2
data modify storage vanilla_refresh_config:config config.blockanims set value 1
data modify storage vanilla_refresh_config:config config.blockanims_beacon set value 1
data modify storage vanilla_refresh_config:config config.blockanims_beacon2 set value 1
data modify storage vanilla_refresh_config:config config.blockanims_witherskull set value 1
data modify storage vanilla_refresh_config:config config.blockanims_brewing set value 1
data modify storage vanilla_refresh_config:config config.blockanims_enchant set value 1
data modify storage vanilla_refresh_config:config config.blockanims_dragonegg set value 1
data modify storage vanilla_refresh_config:config config.blockanims_enderchest set value 1
data modify storage vanilla_refresh_config:config config.blockanims_jukebox set value 1
data modify storage vanilla_refresh_config:config config.blockanims_jukebox2 set value 1
data modify storage vanilla_refresh_config:config config.blockanims_jukebox3 set value 1
data modify storage vanilla_refresh_config:config config.subtitles set value 1
data modify storage vanilla_refresh_config:config config.biome set value 1
data modify storage vanilla_refresh_config:config config.ghost set value 1
data modify storage vanilla_refresh_config:config config.spectate set value 1
data modify storage vanilla_refresh_config:config config.spectate_animation set value 1
data modify storage vanilla_refresh_config:config config.healthsound set value 1
data modify storage vanilla_refresh_config:config config.invis set value 1
data modify storage vanilla_refresh_config:config config.clock set value 1

# --- DISABLED (everything else the audit specifically flagged) ---
data modify storage vanilla_refresh_config:config config.sitting set value 0
data modify storage vanilla_refresh_config:config config.mob_health set value 0
data modify storage vanilla_refresh_config:config config.totem_void set value 0
data modify storage vanilla_refresh_config:config config.ladder set value 0
data modify storage vanilla_refresh_config:config config.homingxp set value 0
data modify storage vanilla_refresh_config:config config.cropsxp set value 0
data modify storage vanilla_refresh_config:config config.path set value 0
data modify storage vanilla_refresh_config:config config.echo set value 0
data modify storage vanilla_refresh_config:config config.babyzombie set value 0
data modify storage vanilla_refresh_config:config config.armortrimmed_mobs set value 0
data modify storage vanilla_refresh_config:config config.lodestone set value 0
data modify storage vanilla_refresh_config:config config.cake set value 0
data modify storage vanilla_refresh_config:config config.soul set value 0
data modify storage vanilla_refresh_config:config config.dragonegg set value 0
data modify storage vanilla_refresh_config:config config.dragonelytra set value 0
data modify storage vanilla_refresh_config:config config.wands_survival set value 0
data modify storage vanilla_refresh_config:config config.gravestone set value 0
