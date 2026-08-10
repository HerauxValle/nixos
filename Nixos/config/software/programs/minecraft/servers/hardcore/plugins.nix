# &desc: "Hardcore server's plugin jars and world/datapacks/ -- Chunky, BlueMap, GrimAC, ClearLaggEnhanced, PlayTimeManager, AdvancedServerList, AntiPopup, VoxyServerSide, MCPanel, LuckPerms, GSit, FastLeafDecay (plugins); Geophilic, AMH, More Mobs, Tool Trims, Dynamic Lights, Spawn Animations, Vanilla Refresh + its whitelist-enforcement override (datapacks). DiscordSRV + Skript + SentientMobs + OmniCut commented out/rejected (see inline comments for why). Spark bundled with Paper, no jar needed; AntiXray skipped, Paper ships it enabled by default. All chosen for zero gameplay advantage/cheating/non-vanilla content -- see conversation for the full reasoning."

{ pkgs, ... }:

let
  # TRUE whitelist -- every known Vanilla Refresh feature forced off
  # except the 14 explicitly approved (no exceptions, not even for
  # features independently verified safe, like Loyal Tridents/Player
  # Head Drop/Recovery Coordinates/anvil sound -- those are off too
  # since they were never in the final approved list). Runs every time
  # the world loads, overwriting whatever Vanilla Refresh's own defaults
  # (or any in-game toggling) set -- unconditional "set value", not the
  # "unless already set" guard Vanilla Refresh itself uses, so this
  # always wins regardless of load order between the two packs'
  # #minecraft:load contributions. See vanilla-refresh-overrides.mcfunction
  # itself for the full per-key reasoning, one comment per line.
  vanillaRefreshOverridesDatapack = pkgs.runCommand "vanilla-refresh-overrides-datapack" { } ''
    mkdir -p $out/data/vr_overrides/function
    mkdir -p $out/data/minecraft/tags/function

    cat > $out/pack.mcmeta <<'EOF'
    {
      "pack": {
        "pack_format": 71,
        "min_format": 71,
        "max_format": 9999,
        "supported_formats": { "min_inclusive": 71, "max_inclusive": 9999 },
        "description": "Vanilla Refresh whitelist enforcement (hardcore)"
      }
    }
    EOF

    cat > $out/data/minecraft/tags/function/load.json <<'EOF'
    {
      "replace": false,
      "values": ["vr_overrides:load"]
    }
    EOF

    cp ${./vanilla-refresh-overrides.mcfunction} $out/data/vr_overrides/function/load.mcfunction
  '';
in
{
  services.minecraft-servers.servers.hardcore.symlinks = {
    "plugins/Chunky.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/fALzjamp/versions/MdY6JATr/Chunky-Bukkit-1.5.3.jar";
      hash = "sha256-Uw0sdDCpajmVc5G3CIvhRNqjEI92ZYltHCOqjdSvMvM=";
    };
    # Commented out for now, not currently wanted -- uncomment to re-add.
    # "plugins/DiscordSRV.jar" = pkgs.fetchurl {
    #   url = "https://cdn.modrinth.com/data/UmLGoGij/versions/ATlquwiT/DiscordSRV-Build-1.30.5.jar";
    #   hash = "sha256-7y+h8usUbHx3QStxkKfdM/H8kSgmg/5FQHc5VUyK7+8=";
    # };
    # PAPER build, not Spigot -- the Spigot jar caused BlueMap to fail
    # world-detection entirely and disable itself ("no valid maps
    # configured") on first boot 2026-08-10, confirmed via its own log
    # warning ("you are using the SPIGOT version of BlueMap ... Things
    # will likely not work correctly!"). Same hash as creative's own
    # BlueMap entry -- confirms this is the right jar.
    "plugins/BlueMap.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/swbUV1cr/versions/K5U1ASjn/bluemap-5.23-paper.jar";
      hash = "sha256-M5VU11ztqzVON2Z3z8cwjEmZUpFYSejimUcY5KFT1k4=";
    };
    # Detects/reverts illegal movement (noclip/fly/speed) -- pure
    # protection against actual client-side cheats or desync glitches,
    # zero effect on legitimate play.
    "plugins/GrimAC.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/LJNGWSvH/versions/fbt7nJt5/grimac-bukkit-2.3.74-2614909.jar";
      hash = "sha256-viF0HZxw9RJBGCgdAJsagxZaIR9TrxDa1LMZb/U8l+0=";
    };
    "plugins/ClearLaggEnhanced.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/KAaZvh09/versions/nlLigbcJ/ClearLaggEnhanced-26.8.0.jar";
      hash = "sha256-MdLk5dxwwix8ssPNA/n3+M839a3aZJ+ZAHIPc4/L4Pk=";
    };
    # Pure stats -- /playtime and friends, no gameplay effect.
    "plugins/PlayTimeManager.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/OzCiibPq/versions/C0SSVnbh/PlayTimeManager-3.6.5.jar";
      hash = "sha256-H3HuF8g5kCVKJUEZNNG8sEyDnVBTIdhMxJRpkEQVCKo=";
    };

    # Customizes the multiplayer-screen server-list entry (MOTD/favicon)
    # -- client-side display only, zero effect on anyone actually
    # connected. Config in files.nix.
    "plugins/AdvancedServerList.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/xss83sOY/versions/6FX9dEc4/AdvancedServerList-Paper-5.9.0.jar";
      hash = "sha256-6eZt3BXkGioOtRdaF80JJhJnq7Et5OmZhpY6k+B5Ev8=";
    };

    # Suppresses the client's "server enforces secure chat" popup --
    # pure client-side annoyance removal, no chat/report mechanic change.
    "plugins/AntiPopup.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/HFTnFHKn/versions/vdjyDvoq/AntiPopup-13.2.jar";
      hash = "sha256-7Ds657LDwLCJ6/cDiOHlfPB3s5YV2XeuvYOahHsILeE=";
    };

    # Bedrock-client cross-play proxy -- who can join, not what they can
    # do once in, so no advantage/mechanic implications either way. Same
    # "Spigot" plugin-mode jar as creative/plugins.nix's entry.
    "plugins/Geyser-Spigot.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/wKkoqHrH/versions/tQFyivtA/Geyser-Spigot.jar";
      hash = "sha256-efNudSvfb7na79Nat1OHu2ce+U829a7eNraXpOFLsS8=";
    };

    # Live /vdt commands to change view/simulation-distance without a
    # restart -- purely a server-performance knob, same for every
    # player, no advantage/mechanic change. Default config ships with
    # auto-adjust (TPS-based dynamic scaling) OFF, so installing this
    # changes nothing on its own -- server.properties' 32/32 stays the
    # real, restart-persistent value. A manual /vdt set only changes the
    # live in-memory value via Paper's own World#setViewDistance API, it
    # doesn't touch server.properties or this plugin's own config, so it
    # reverts back to 32/32 on the next restart.
    "plugins/ViewDistanceTweaks.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/X7x1kZUF/versions/Uorl1raS/view-distance-tweaks-2.6-RELEASE.jar";
      hash = "sha256-cP+P8d0B3ziLlcGhyozE7iLfwgN6CdKGBZSFZgG+sFA=";
    };

    # NOT added: AntiXray -- Paper's own paper-world-defaults.yml already
    # ships anti-xray enabled by default (anticheat.anti-xray.enabled:
    # true, engine-mode: 2), confirmed via PaperMC's own docs. A plugin
    # would be redundant.

    # Streams real generated (not fake/synthetic) chunk data as LODs
    # beyond simulation-distance -- a genuine foreknowledge advantage if
    # left at its default 512-chunk radius (structures included, since
    # it's real chunk data). lodDistanceChunks in files.nix's
    # vss-server-config.json is the only real nerf knob.
    "plugins/VoxyServerSide.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/84zcagOb/versions/zI7Q9rlu/voxy-server-side-paper.jar";
      hash = "sha256-QLM8ASeYLZrW1zzCKjCNpwsxO9C5+agfMc043cnj3Ds=";
    };

    # Web console (browser-based, its own built-in HTTP server, no RCON
    # needed). Officially only lists support through 26.1.2 -- it's a
    # pure Bukkit-API/HTTP-server tool with no NMS/version-specific game
    # logic though, so likely still works unofficially on 26.2. Verify
    # after first boot; revert to a manual mcrcon/tmux console if it
    # doesn't load cleanly.
    "plugins/MCPanel.jar" = pkgs.fetchurl {
      url = "https://hangarcdn.papermc.io/plugins/VenDooM/MC-Server-Admin-Panel/versions/1.2.4/PAPER/MCPanel-1.2.4.jar";
      hash = "sha256-jiOzvdawid0TnFnPzLKC8KPeAeNYrGZwrwrTgasa+So=";
    };

    # Permissions plugin -- fixes PlayTimeManager's "LuckPerms plugin
    # configured but not found" warning, and lets you grant fine-grained
    # command permissions to non-op players (e.g. for command-alias/
    # logic plugins below) without giving full op. NOT wired to grant
    # any gameplay-affecting permission node by default -- op status
    # (gamemode/etc.) stays exactly as restricted as before (ops.nix).
    # Same jar/hash as creative's own LuckPerms entry.
    "plugins/LuckPerms.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/Vebnzrzj/versions/b0mk8uS6/LuckPerms-Bukkit-5.5.71.jar";
      hash = "sha256-Sc7LZvof0ioTMDmkkOnB5QlaI4581m650qFv5siXVQ0=";
    };

    # Sit/lay/crawl on right-click or /sit -- purely cosmetic animation,
    # zero gameplay effect.
    "plugins/GSit.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/GOHbQGyX/versions/nZM8fxpG/GSit-3.5.1.jar";
      hash = "sha256-sHSUErZcAb3NaDggp2Si92msVX6wtpGFbSZ6Y/KDyhw=";
    };

    # Leaves decay faster after their connected logs are broken instead
    # of floating there for a while -- pure time/visual convenience, no
    # change to drops or resources.
    "plugins/FastLeafDecay.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/FnE6S0Zk/versions/wGh1RBAz/FastLeafDecay-1.0.7.jar";
      hash = "sha256-T6+4/M/4G3KV1abyB1IMe2QLITTdV725niuqe7iJR+I=";
    };

    # Geophilic -- vanilla biome decoration (fallen trees, boulders, tree
    # stumps, bushes, moss, forest clearings) using only vanilla blocks,
    # no new blocks/items/biomes at all (confirmed via its own
    # description). A datapack, not a plugin, so it lives under
    # world/datapacks/ instead of plugins/ -- the actively-maintained
    # builds are otherwise Fabric/Forge mods (incompatible with Paper),
    # but this specific datapack sibling build genuinely lists 26.2
    # support. CAVEAT: datapacks only affect newly-generated chunks --
    # whatever's already generated near spawn from earlier test boots
    # won't retroactively decorate, only unexplored terrain going
    # forward.
    "world/datapacks/Geophilic.zip" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/hl5OLM95/versions/6uLCMJCR/Geophilic%20v3.6.dp.zip";
      hash = "sha256-O+eVkgCWVzwhZ7zQh4DnApOB3V4reCaATfPikpQzbVQ=";
      name = "geophilic-3.6-datapack.zip";
    };

    # All Mob Heads -- every mob can drop a decorative head, plus
    # renaming-based guaranteed conversion for otherwise-unspawnable
    # trophies (Illusioner, Zombie Horse, Killer Bunny). No power/
    # resource gain, purely a collection/decoration feature -- confirmed
    # via its own description.
    "world/datapacks/AMH.zip" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/WYMK8lIp/versions/DX4ioZzs/AllMobHeads_V11.1.zip";
      hash = "sha256-ObNGU5lSyIu1Wn4d/GapTeNKbIaYt2quMlYz7ryrGaU=";
      name = "amh-v11.1-datapack.zip";
    };

    # More Mobs -- 85 custom player-head visual variants for existing
    # hostile mobs, plus spiders hanging upside-down. Confirmed purely
    # decorative, no new items/blocks/mechanics.
    "world/datapacks/MoreMobs.zip" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/HJR6V0I2/versions/agFrBfr8/more_mobs-v1.5.10-mc1.14-26.2.9-datapack.zip";
      hash = "sha256-2ciuT9Xn9/ft776Rg6YBnH5t1CmmeMNpTkheucN7A1Y=";
      name = "more-mobs-v1.5.10-datapack.zip";
    };

    # Tool Trims -- same visual trim system armor already has, extended
    # to 46 tools via 4 new smithing templates. Zero stat/durability/
    # enchantability changes, confirmed via its own description.
    "world/datapacks/ToolTrims.zip" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/uXeEiQk1/versions/26fWzOv5/tool-trims-v3.0.7-for-1.21.11%2B.zip";
      hash = "sha256-CluKwP21aDRaGKUK3kmXykOCPorjeZ1k+Mzm1IPb0f0=";
      name = "tool-trims-v3.0.7-datapack.zip";
    };

    # Dynamic Lights -- held/dropped light-emitting items actually
    # illuminate the area, via real vanilla light blocks that follow the
    # player. NOTE: unlike the other datapacks here, this has a genuine
    # (if minor) gameplay effect -- it raises the actual light level
    # around you, which suppresses hostile mob spawns nearby, something
    # holding (not placing) a torch doesn't do in vanilla. Added anyway
    # per your explicit call.
    "world/datapacks/DynamicLights.zip" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/7YjclEGc/versions/3SxZhstR/dynamiclights-v1.9.3-mc1.17-26.2.9-datapack.zip";
      hash = "sha256-FmOrPmUhXfBjIJd3df9Y2bTvUDZhTlhZ1v3PB8tNUVg=";
      name = "dynamic-lights-v1.9.3-datapack.zip";
    };

    # Spawn Animations -- hostile mobs dig out of the ground / poof in
    # instead of just appearing. Confirmed purely visual, zero mechanic
    # changes (health/spawn-rate/difficulty untouched).
    "world/datapacks/SpawnAnimations.zip" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/zrzYrlm0/versions/kXr2QX8r/spawnanimations-v1.11.5-mc1.17-26.2.9-datapack.zip";
      hash = "sha256-2IxrHOtb3QJn7CtQQNR2k6dXD8TObtsiDS3JmGtLL0A=";
      name = "spawn-animations-v1.11.5-datapack.zip";
    };

    # Vanilla Refresh -- a large, individually-toggleable QoL/cosmetic
    # feature bundle. Only 14 of its 60+ features are actually wanted
    # here (everything else -- including a genuine lodestone-teleport
    # mechanic, free XP/crop XP, an easier-baby-zombie buff, and a cake
    # side effect that silently drops free sugar+wheat -- audited and
    # rejected). See vanillaRefreshOverridesDatapack above and
    # vanilla-refresh-overrides.mcfunction for the actual enforcement:
    # this jar alone is NOT the full picture, it must be paired with
    # that override datapack (added right below) or the plugin's own
    # defaults (which include several rejected features) apply instead.
    "world/datapacks/VanillaRefresh.zip" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/gWO6Zqey/versions/n4kxzqW2/vanilla-refresh-1.4.31.zip";
      hash = "sha256-RmRh2Hu9yAdJSNtPbKdtLUI+C/FFXI7PWGtoyNkyCrs=";
      name = "vanilla-refresh-1.4.31-datapack.zip";
    };

    # The override datapack itself -- "zzz_" prefix has no functional
    # significance (datapack load order for shared function tags doesn't
    # depend on folder name), it's just there so this sorts visibly last
    # in a directory listing next to VanillaRefresh's own files.
    "world/datapacks/zzz_VanillaRefreshOverrides" = vanillaRefreshOverridesDatapack;

    # NOT added: SentientMobs -- looked like pure combat-AI difficulty on
    # the surface, but its real config has an entire villager economy
    # (labor-trade, profession-work, farmer-work, community chests, an
    # auto-spawning golem defender) nested under `villager.*` and still
    # active regardless of the plugin's own top-level (decoy/legacy)
    # toggles for the same things. Not worth the complexity/removal risk
    # for what we actually wanted (harder combat only).

    # Commented out -- no alias in mind yet. Simple command ALIASING
    # (shortcut to an existing command, e.g. /hub -> /mvtp hub) needs no
    # plugin at all -- see files.nix's commented commands.yml block.
    # This is only for actual NEW commands with their own logic/tab-
    # completion. Skript is the example here since it's already a known
    # dependency elsewhere in this repo (minecraft-worlds.nix's hardcore
    # permadeath script) -- same jar/hash, so uncommenting this is a
    # known-good starting point, not unresearched. Tell me what you want
    # the command(s) to actually do and I'll help write the script +
    # grant the right (non-cheat) LuckPerms permission node for it.
    # "plugins/Skript.jar" = pkgs.fetchurl {
    #   url = "https://cdn.modrinth.com/data/xFNYAvMk/versions/9s2QlgIA/Skript-2.16.1.jar";
    #   hash = "sha256-g1ejSLJ82KLPdJmY5K0UvR3KMWACa9MELW0Xz7TJinA=";
    # };
  };
}
