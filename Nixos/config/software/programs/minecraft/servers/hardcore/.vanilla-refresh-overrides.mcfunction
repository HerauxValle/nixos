# &desc: "mcfunction enforcing a TRUE whitelist for Vanilla Refresh -- every feature forced off except the 14 explicitly approved, packaged into a companion datapack by plugins.nix's vanillaRefreshOverridesDatapack."
#
# Unconditional "set value" (no "unless" guard), so this always wins
# regardless of load order relative to vanilla_refresh:load -- it
# doesn't matter what Vanilla Refresh's own defaults are, this function
# is the single source of truth every time the world loads.
#
# One line per known config key from Vanilla Refresh 1.4.31's own
# default_settings.mcfunction, each with the reason it's on or off.
# Pure numeric sub-parameters (torch_speed, soul_despawntime, etc.) are
# skipped entirely -- they're inert once their parent boolean toggle is
# forced to 0 below, so setting them too would be meaningless.

# ================= THE 14 APPROVED FEATURES (ON) =================
data modify storage vanilla_refresh_config:config config.daycounter set value 1
# -- Day Counter: announces the current day number. Pure flavor text.
data modify storage vanilla_refresh_config:config config.craftsound set value 1
# -- Craft Sounds: sound/particle burst when crafting. Audio-only, verified no loot/buff.
data modify storage vanilla_refresh_config:config config.jukebox set value 1
# -- Jukebox Music Override: jukebox music overrides background music. Audio-only.
data modify storage vanilla_refresh_config:config config.armorstand set value 1
# -- Better Armor Stands: poseable arms/tool rack. Verified no loot/buff.
data modify storage vanilla_refresh_config:config config.witherhead set value 1
# -- Wither Head Drop: cosmetic trophy head, verified zero stat components.
data modify storage vanilla_refresh_config:config config.banner set value 2
# -- Equipable Banners: wear a banner as a cosmetic hat. 2 is this pack's own "on" default value.
data modify storage vanilla_refresh_config:config config.anim_level set value 1
data modify storage vanilla_refresh_config:config config.anim_water set value 1
data modify storage vanilla_refresh_config:config config.anim_teleport set value 1
# -- Improved Player Animations (leveling/water-splash/teleport). Visual only.
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
# -- Improved Block Animations (beacon/brewing/enchanting/etc). Visual only.
data modify storage vanilla_refresh_config:config config.subtitles set value 1
# -- Subtitles on Major Events: title-card for progression milestones. Text only.
data modify storage vanilla_refresh_config:config config.biome set value 1
# -- Subtitles on Biome Discovery: announces biome name on entry. Text only, same info as F3.
data modify storage vanilla_refresh_config:config config.ghost set value 1
data modify storage vanilla_refresh_config:config config.spectate set value 1
data modify storage vanilla_refresh_config:config config.spectate_animation set value 1
# -- Spectator Ghost: particle effects while spectating. You'll be here a lot post-death.
data modify storage vanilla_refresh_config:config config.healthsound set value 1
# -- Low Health Sound: heartbeat sound at critical health. Redundant with vanilla's own red-pulse warning, no new info.
data modify storage vanilla_refresh_config:config config.invis set value 1
# -- Stands/Frames Invisibility: potion-invisible armor stands/item frames. Cosmetic.
data modify storage vanilla_refresh_config:config config.clock set value 1
# -- Readable Clocks: exact time readout holding a clock. Same info the sun/moon position already gives.

# ================= EVERYTHING ELSE (OFF) =================
# Not in the approved 14 -- forced off regardless of whether it's
# individually harmless, per an explicit "true whitelist, no exceptions"
# instruction, even for features already verified safe below.

data modify storage vanilla_refresh_config:config config.sitting set value 0
# -- Player Sitting: redundant, GSit plugin already covers this.
data modify storage vanilla_refresh_config:config config.mob_health set value 0
# -- Mob Health Display: reveals more combat info than vanilla ever shows.
data modify storage vanilla_refresh_config:config config.death set value 0
# -- unclear/unaudited death-message toggle, not approved.
data modify storage vanilla_refresh_config:config config.death_sound set value 0
data modify storage vanilla_refresh_config:config config.death_sound_local set value 0
# -- Improved Death Sound: not in the final approved 14, off even though cosmetic-only.
data modify storage vanilla_refresh_config:config config.totem_void set value 0
# -- Totem Works In Void: removes a genuine permadeath risk, exactly what hardcore shouldn't soften.
data modify storage vanilla_refresh_config:config config.ladder set value 0
# -- Drop Ladder: skips manual ladder-placement effort.
data modify storage vanilla_refresh_config:config config.death_items set value 0
# -- Death-message item display: not in the final approved 14, off even though display-only.
data modify storage vanilla_refresh_config:config config.torch set value 0
# -- Unaudited torch-related mechanic, not approved.
data modify storage vanilla_refresh_config:config config.tips_mc set value 0
data modify storage vanilla_refresh_config:config config.tips_refresh set value 0
# -- Tip messages, not approved, off.
data modify storage vanilla_refresh_config:config config.grief_tnt set value 1
data modify storage vanilla_refresh_config:config config.grief_crystal set value 1
data modify storage vanilla_refresh_config:config config.grief_lava set value 1
# -- Anti-grief toggles: value 1 is CONFIRMED to mean "completely normal, unmodified vanilla
#    explosion behavior" (traced to source) -- this is not "on" in the enable sense, it's
#    "don't touch vanilla" and is required to keep TNT/crystal/lava griefing fully vanilla.
data modify storage vanilla_refresh_config:config config.explosivefurnace set value 0
# -- Unaudited furnace-explosion mechanic, not approved.
data modify storage vanilla_refresh_config:config config.spyglass set value 0
# -- Not in the final approved 14, off.
data modify storage vanilla_refresh_config:config config.dragonelytra set value 0
# -- Enderdragon Drops Elytra: massive itemization advantage, always off.
data modify storage vanilla_refresh_config:config config.soul set value 0
data modify storage vanilla_refresh_config:config config.soul_create set value 0
data modify storage vanilla_refresh_config:config config.soul_otherplayer set value 0
# -- Soul Links: keeps a % of items/XP on death -- directly undermines hardcore permadeath stakes.
data modify storage vanilla_refresh_config:config config.dragonegg set value 0
# -- Renewable Dragon Eggs: resource-duplication-adjacent advantage, always off.
data modify storage vanilla_refresh_config:config config.homingxp set value 0
# -- Homing Experience Orbs: guaranteed XP collection at range, a real resource advantage.
data modify storage vanilla_refresh_config:config config.cropsxp set value 0
# -- Crops XP: new XP source that doesn't exist in vanilla.
data modify storage vanilla_refresh_config:config config.trident set value 0
# -- Loyal Tridents: verified as a pure bug-fix (void-thrown Loyalty tridents never return in
#    vanilla), but not in the final approved 14 -- off per true-whitelist, no exceptions.
data modify storage vanilla_refresh_config:config config.tabdisplay set value 0
# -- Tab-list playtime display, not approved, off.
data modify storage vanilla_refresh_config:config config.cyclestats set value 0
data modify storage vanilla_refresh_config:config config.cyclestats_health set value 0
# -- Below-name stat cycling display, not approved, off.
data modify storage vanilla_refresh_config:config config.path set value 0
# -- Path Sprinting: mobility/speed advantage on paths.
data modify storage vanilla_refresh_config:config config.lodestone set value 0
# -- Lodestone: a genuine ender-pearl-to-lodestone TELEPORT mechanic, same category as
#    Waystones which you already ruled out. Always off.
data modify storage vanilla_refresh_config:config config.recovery set value 0
# -- Recovery Coordinates: near-inert for hardcore anyway, but not in the final approved 14 -- off.
data modify storage vanilla_refresh_config:config config.compass set value 0
# -- Not in the final approved 14, off.
data modify storage vanilla_refresh_config:config config.echo set value 0
# -- Echo Shard Silence: stealth-from-mobs advantage.
data modify storage vanilla_refresh_config:config config.command_block set value 0
# -- Admin/creative feature, irrelevant to survival, off.
data modify storage vanilla_refresh_config:config config.giveclearing set value 0
# -- Unaudited inventory-related mechanic, not approved.
data modify storage vanilla_refresh_config:config config.wands_survival set value 0
# -- Creative-mode wands usable in survival -- definitely off.
data modify storage vanilla_refresh_config:config config.cake set value 0
# -- Party Cake: confirmed to also silently drop free sugar+wheat, a real resource advantage.
data modify storage vanilla_refresh_config:config config.join set value 0
data modify storage vanilla_refresh_config:config config.firstjoin set value 0
# -- Join/first-join messages, irrelevant solo, not approved, off.
data modify storage vanilla_refresh_config:config config.anvil set value 0
# -- Anvil sound-pitch variation: verified cosmetic-only, but not in the final approved 14 -- off.
data modify storage vanilla_refresh_config:config config.babyzombie set value 0
# -- Improved Baby Zombies: reduces baby zombie health, a direct combat advantage
#    (bundled with a harder sprint-jump too, but the net buff-to-player disqualifies it).
data modify storage vanilla_refresh_config:config config.ghost_toggle set value 0
# -- Per-player override flag for the ghost feature, not needed, off.
data modify storage vanilla_refresh_config:config config.itemsparkle set value 0
# -- Not in the final approved 14, off.
data modify storage vanilla_refresh_config:config config.playerlist set value 0
# -- Tab-list feature, not approved, off.
data modify storage vanilla_refresh_config:config config.armortrimmed_mobs set value 0
# -- Trimmed Armored Piglins spawn-rate boost: better loot-mob spawn chance, a real advantage.
data modify storage vanilla_refresh_config:config config.gamerules set value 0
# -- Vanilla Refresh's own gamerule-management meta-toggle, not approved, off (don't let it
#    touch gamerules at all).
data modify storage vanilla_refresh_config:config config.stats set value 0
data modify storage vanilla_refresh_config:config config.stats_time set value 0
data modify storage vanilla_refresh_config:config config.stats_mobkills set value 0
data modify storage vanilla_refresh_config:config config.stats_kills set value 0
data modify storage vanilla_refresh_config:config config.stats_deaths_non_pvp set value 0
data modify storage vanilla_refresh_config:config config.stats_deaths set value 0
data modify storage vanilla_refresh_config:config config.stats_deathtime set value 0
data modify storage vanilla_refresh_config:config config.stats_deathaverage set value 0
data modify storage vanilla_refresh_config:config config.stats_deathaverage_non_pvp set value 0
data modify storage vanilla_refresh_config:config config.stats_member_id set value 0
data modify storage vanilla_refresh_config:config config.stats_xp set value 0
data modify storage vanilla_refresh_config:config config.stats_health set value 0
data modify storage vanilla_refresh_config:config config.stats_memberjoin set value 0
# -- Stat-tracking/below-name-health-display suite, not approved, off.
data modify storage vanilla_refresh_config:config config.gravestone set value 0
# -- Gravestone-on-death item recovery: a real hardcore-softening advantage, always off.
data modify storage vanilla_refresh_config:config config.stoptime set value 0
# -- Freezing the day/night cycle is exploit-adjacent (avoid night indefinitely), always off.
data modify storage vanilla_refresh_config:config config.playerheads set value 0
# -- Player Head Drop: verified cosmetic-only, but not in the final approved 14 -- off.
data modify storage vanilla_refresh_config:config config.soul_percentxp set value 0
data modify storage vanilla_refresh_config:config config.soul_takeitems set value 0
# -- Soul Links sub-parameters, moot since soul is off, set to neutral anyway.
data modify storage vanilla_refresh_config:config config.jukebox_stop_sound set value 0
data modify storage vanilla_refresh_config:config config.death_stop_music set value 0
# -- Minor audio behaviors, not approved, off.
data modify storage vanilla_refresh_config:config config.process_stats set value 0
# -- Internal stat-processing toggle, not approved, off.
