# &desc: "Creative server's plugin jars -- Multiverse (worlds/nether-end linking), BlueMap, the building-tool stack (FAWE/WorldGuard/Axiom/etc), Typewriter + its extensions (dialogue/cutscene/questing), Geyser (Bedrock cross-play), OpenCreative commented out (not installed)."

{ pkgs, config, ... }:

{
  services.minecraft-servers.servers.creative.symlinks = {
    "plugins/Multiverse-Core.jar" = pkgs.fetchurl {
      url = "https://github.com/Multiverse/Multiverse-Core/releases/download/5.7.3/multiverse-core-5.7.3.jar";
      hash = "sha256-yRp8LCWtfYeCV7CMmAOB6LX/uo32P69AIkK/tWoFiIQ=";
    };
    "plugins/BlueMap.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/swbUV1cr/versions/K5U1ASjn/bluemap-5.23-paper.jar";
      hash = "sha256-M5VU11ztqzVON2Z3z8cwjEmZUpFYSejimUcY5KFT1k4=";
    };
    # TRIED, DOESN'T WORK: F3NPerm (last build only claims support
    # through 1.21.5, and its NMS reflection provider guesses wrong on
    # 26.1.2 -- "Could not recognize server version", picks
    # ReflectionProvider_1_21_3). F3+F4's gamemode switcher GUI checks
    # vanilla OP status directly, bypassing Bukkit's permission system
    # entirely, and no other plugin fills this gap -- documented "won't
    # fix" in Paper's own issue tracker (#4986/#13489). No server-side
    # fix exists on this version. Use the actual /gamemode command
    # instead -- that IS correctly scoped per world via LuckPerms (see
    # modules/services/minecraft-worlds/minecraft-worlds.nix's
    # mkGamemodePermCmds).
    # Auto-links each world-group's own nether/end by naming convention
    # (redstone -> redstone_nether/redstone_the_end, building ->
    # building_nether/building_the_end, etc.) -- no per-world config needed.
    "plugins/Multiverse-NetherPortals.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/vtawPsTo/versions/RRa80eDI/multiverse-netherportals-5.1.0.jar";
      hash = "sha256-pLN1CXC1txCqlCuq/weo/O9WgCzyhrnc2n5p3ZBEksw=";
    };

    "plugins/FastAsyncWorldEdit.jar" = pkgs.fetchurl {
      # 2.15.1/2.15.2/2.15.3 (every released build) crash with
      # ArrayIndexOutOfBoundsException/NoSuchElementException in
      # BlockTypes init during WorldInitEvent -- root cause is
      # IntellectualSites/FastAsyncWorldEdit#3602 (registry entries
      # missing for newer 1.21.x block types), fixed upstream in
      # commit a7c959f right after the 2.15.3 tag. Not in any Modrinth
      # release yet, so pulling straight from their Jenkins CI:
      # 2.15.4-SNAPSHOT build #1362 (https://ci.athion.net/job/FastAsyncWorldEdit/1362/).
      # Jenkins build artifacts aren't permanent -- if this URL 404s
      # later, check for a proper 2.15.4 release on Modrinth first.
      url = "https://ci.athion.net/job/FastAsyncWorldEdit/1362/artifact/artifacts/FastAsyncWorldEdit-Paper-2.15.4-SNAPSHOT-1362.jar";
      hash = "sha256-yW0ddZRwSOP9VvKtL8letvRg0vvUxnf9tKc7qT6rd44=";
    };
    "plugins/WorldGuard.jar" = pkgs.fetchurl {
      # Depends on a WorldEdit-API-compatible plugin -- FAWE above satisfies that.
      url = "https://cdn.modrinth.com/data/DKY9btbd/versions/btHBavWa/worldguard-bukkit-7.0.18.jar";
      hash = "sha256-CPPvWLxSHGNdjHiu2sqW8VHS05fnzYAYWElV3XRo6wU=";
    };
    "plugins/FastAsyncVoxelSniper.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/D7XBSI1y/versions/n77tXMjA/fastasyncvoxelsniper-3.2.4.jar";
      hash = "sha256-k1qgEacp/UDLh/0+Nxwg3UWBMDVH1PksMcvGCOfl7LM=";
    };
    "plugins/BuildersUtilities.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/5GTPKiuo/versions/eqxlPPvN/BuildersUtilities-1.9.1.jar";
      hash = "sha256-cvPXZV13SGIFp2fJF5HfJwab/KJyhwLr/Zvpd30uzpM=";
    };

    "plugins/AxiomPaper.jar" = pkgs.fetchurl {
      # 2026-08-09: client was on a 26.1.2 modpack (Axiom-5.4.2-for-MC26.1.jar)
      # while this ran the 26.2 build -- data version mismatch (client 4790,
      # server 4903), since AxiomPaper's version numbers don't track the
      # closed-source Axiom client mod's at all. Tried swapping the server
      # to the 26.1 build to match; still mismatched (same 5.0.4 plugin
      # version, same data version regardless of MC-target build). Resolved
      # by moving the *client* to 26.2 instead -- this 26.2 build is correct
      # again now.
      url = "https://cdn.modrinth.com/data/evkiwA7V/versions/Ow8CJ6pP/AxiomPaper-5.0.4-for-MC26.2.jar";
      hash = "sha256-PWA0Lb03g0M37MTcQ5MexwCSzxuGsEt7l4jfGIR55CI=";
    };

    # REMOVED: CoreProtect -- version 24.0 (latest, targets 26.1.x) hard
    # version-gates: "Minecraft 26.2 is not supported.", self-disables on
    # enable. Worse, AxiomPaper's own CoreProtect integration probe
    # (com.moulberry.axiom.integration.coreprotect) still tries to load
    # its class regardless of enabled state and throws
    # NoClassDefFoundError, which crashed AxiomPaper's own onEnable
    # entirely -- confirmed in the wild 2026-08-09. Revisit once
    # CoreProtect ships a real 26.2 build.
    "plugins/Chunky.jar" = pkgs.fetchurl {
      # Same story -- no 26.2 build yet, latest targets 26.1.x.
      url = "https://cdn.modrinth.com/data/fALzjamp/versions/MdY6JATr/Chunky-Bukkit-1.5.3.jar";
      hash = "sha256-Uw0sdDCpajmVc5G3CIvhRNqjEI92ZYltHCOqjdSvMvM=";
    };
    "plugins/HeadDB.jar" = pkgs.fetchurl {
      # No 26.2 build exists yet either (still capped at 1.21.11) --
      # best-effort, verify it still loads after the bump.
      url = "https://cdn.modrinth.com/data/cRS8VY4i/versions/KeAgbpca/HeadDB-6.0.1.jar";
      hash = "sha256-3EBA6y8RHPFd9fl0k6ycr1wIeYSIP4Oy7yJe9d9eFv8=";
    };

    # Premium plugin from Patreon, kept out of the Nix store (paid
    # download, not redistributable) -- string interpolation here
    # instead of a Nix path literal, so ln -sf gets this literal path
    # rather than a store-copied one.
    #
    # All 3 stock local builds crash/self-disable against this Paper
    # 26.2 server (2026-08-09): 0.5.6 and 0.5.5 throw
    # NumberFormatException: For input string: "craftbukkit" while
    # enabling, 0.5.4 self-disables ("This version is not supported
    # for Arceon!"). Root cause in 0.5.6's obfuscated
    # com/arceon/core/h/n.class: modern Paper's unversioned
    # "org.bukkit.craftbukkit" package name (no more "v1_20_R1"-style
    # suffix) breaks the version-string parsing that feeds a
    # server-version-gate check, which then tries to Integer.parseInt
    # the literal string "craftbukkit" and throws.
    #
    # -1.20+-patched.jar is a hand-patched copy of the stock 0.5.6 jar
    # (built from a copy in this repo's scratchpad, not committed --
    # regenerate if lost): the crashing method's `getstatic a` at
    # bytecode offset 2009 was changed to `getstatic b`. Field b is a
    # separate, hardcoded, always-valid "v26_1_99" string set
    # unconditionally at the very top of the class's static
    # initializer -- untouched by the broken branch that leaves field
    # a stale as "craftbukkit". A pure constant-pool-index edit (one
    # byte), no bytecode length change, no new branches, so no
    # StackMapTable frame issues. Confirmed working end-to-end
    # (loads, enables, loads config/fonts, no errors) 2026-08-09.
    # Re-patch against a newer Arceon release if Patreon ships one --
    # this exact byte offset is 0.5.6-specific.
    "plugins/Arceon.jar" = "${config.vars.minecraft.premiumAddons}/plugins/arceon/Arceon-0.5.6-1.20+-patched.jar";

    # NOT server-side: "Arceon x Axiom" is a Fabric CLIENT mod
    # (fabric.mod.json, "client"-only entrypoint, requires
    # fabricloader) -- it's the client half of Axiom's Arceon
    # integration, meant for your Fabric/Prism modpack alongside
    # Axiom's own client mod, not Paper's plugins/. Paper's loader
    # correctly refuses it ("does not contain a paper-plugin.yml or
    # plugin.yml"). Install it client-side instead if you want it.

    # SKIPPED: ezEdits (Patreon/Discord-supporter gated, no public URL
    # -- you said skip), Schematic Brush Reborn 2 (SpigotMC direct
    # download is behind a Cloudflare bot-challenge, couldn't fetch it
    # programmatically -- get me a direct file/URL if you still want it).

    # Item editor -- rename/lore/enchant/attribute/potion-color/firework
    # GUIs. An admin/creative tool by nature, wrong fit for hardcore's
    # no-advantage rule but exactly right here since you're a real op on
    # this server (ops.nix).
    "plugins/ItemEdit.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/yx81EHRu/versions/ODZyheTG/ItemEdit-3.7.10.jar";
      hash = "sha256-xMzh9A/u+AubB/+Y3w/z2vjkoSI0ddmf/w7NeMy1Yts=";
    };

    # NOT ENABLED -- OpenCreative+ itself has no hard dependencies
    # (confirmed via its own Modrinth listing), only optional
    # integrations: Vault (economy), ProtocolLib (coding-chest
    # animations/glow highlighting), LibsDisguises (entity disguise
    # action), PlaceholderAPI. None of those four are installed here, so
    # it would run but with those specific extra features silently
    # inert. Commented out per your ask -- uncomment to actually add it.
    # "plugins/OpenCreative.jar" = pkgs.fetchurl {
    #   url = "https://cdn.modrinth.com/data/pMgywsVc/versions/BVlq6foS/opencreative-6.0.0-build-273.jar";
    #   hash = "sha256-5p4zFCRG1t2fDXv17uaqrC7/9TWg1Hh+Yi/rcJ1FNds=";
    # };

    # Required hard dependency of Typewriter itself (confirmed via
    # Modrinth's own dependency listing for the project) -- packet
    # interception library, not something Typewriter can run without.
    "plugins/PacketEvents.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/HYKaKraK/versions/h0ncTpUP/packetevents-spigot-2.13.0.jar";
      hash = "sha256-bZ7ODYfucnp5ogt/+9QyAhYJxvUrr8tlT8LT6bbwZMU=";
    };

    # Dialogue/cutscene/questing engine -- NPCs, branching conversations,
    # cinematics. PlaceholderAPI is an optional soft-dependency (extra
    # placeholders in text) not installed here, everything else works
    # without it. Geyser (added below) is also an optional soft-dep, for
    # Bedrock-client dialogue UI support -- already satisfied.
    "plugins/Typewriter.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/Vm7B3ymm/versions/NWX8MGts/Typewriter-0.9.0-beta-175.jar";
      hash = "sha256-JljCzMceuDibGE882S5mH/pHXA3FZJFB9v47dpUXcHk=";
    };

    # Typewriter's extensions -- shipped as separate jars attached to the
    # SAME Modrinth version as the core plugin above (must be kept in
    # lockstep on updates, confirmed via Typewriter's own install docs).
    # Core content extensions (no third-party plugin needed) stay
    # enabled; integration adapters for plugins we don't run here are
    # commented out -- installing them wouldn't crash anything, they'd
    # just sit there offering entry types for a plugin (Citizens,
    # MythicMobs, RPGRegions, SuperiorSkyblock2, Vault, WorldGuard) that
    # isn't present, so there's nothing for them to actually do.
    "plugins/Typewriter/extensions/BasicExtension.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/Vm7B3ymm/versions/NWX8MGts/BasicExtension.jar";
      hash = "sha256-16yShUv4wSLGCOsH0D+kJ6ou5HWJ1SUJjEV9fIpBKk8=";
    };
    "plugins/Typewriter/extensions/EntityExtension.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/Vm7B3ymm/versions/NWX8MGts/EntityExtension.jar";
      hash = "sha256-IDk3NitQQR93NHoSvg1Z79f++8TMyc7pNW57/boQz+M=";
    };
    "plugins/Typewriter/extensions/QuestExtension.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/Vm7B3ymm/versions/NWX8MGts/QuestExtension.jar";
      hash = "sha256-vm6guRC4EVbwq5lkQ6+2F/o5tFa7gLQlG8KQc/7GItU=";
    };
    "plugins/Typewriter/extensions/RoadNetworkExtension.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/Vm7B3ymm/versions/NWX8MGts/RoadNetworkExtension.jar";
      hash = "sha256-rKb+8wuFR1ftiNTdedsnMTgoxwkQ33d6xVmBvaSmuJ8=";
    };

    # NOT ENABLED -- integration adapters for plugins not installed on
    # this server. Uncomment whichever ones you add the matching plugin
    # for later (must re-match Typewriter's own version -- see comment
    # above).
    # "plugins/Typewriter/extensions/CitizensExtension.jar" = pkgs.fetchurl {
    #   # Needs Citizens (NPC plugin) -- not installed.
    #   url = "https://cdn.modrinth.com/data/Vm7B3ymm/versions/NWX8MGts/CitizensExtension.jar";
    #   hash = "sha256-HV4IbRVe8eepbiAtMnaJdnQrOFS2W9HrYu6u3hK+puw=";
    # };
    # "plugins/Typewriter/extensions/MythicMobsExtension.jar" = pkgs.fetchurl {
    #   # Needs MythicMobs -- not installed.
    #   url = "https://cdn.modrinth.com/data/Vm7B3ymm/versions/NWX8MGts/MythicMobsExtension.jar";
    #   hash = "sha256-6pdNokCHnked/8kIhMOnGIzTBq98XUXrK0CXqqdm5kM=";
    # };
    # "plugins/Typewriter/extensions/RPGRegionsExtension.jar" = pkgs.fetchurl {
    #   # Needs RPGRegions -- not installed.
    #   url = "https://cdn.modrinth.com/data/Vm7B3ymm/versions/NWX8MGts/RPGRegionsExtension.jar";
    #   hash = "sha256-wDP8FQmP1NaERz1a4urk1sTw3EFHC4UBfjQwS4I6afM=";
    # };
    # "plugins/Typewriter/extensions/SuperiorSkyblockExtension.jar" = pkgs.fetchurl {
    #   # Needs SuperiorSkyblock2 -- not installed.
    #   url = "https://cdn.modrinth.com/data/Vm7B3ymm/versions/NWX8MGts/SuperiorSkyblockExtension.jar";
    #   hash = "sha256-HPkhKWaEVAFM7AmdaDhRqigEzXwUKaTFMHZarmBsn3U=";
    # };
    # "plugins/Typewriter/extensions/VaultExtension.jar" = pkgs.fetchurl {
    #   # Needs Vault -- not installed.
    #   url = "https://cdn.modrinth.com/data/Vm7B3ymm/versions/NWX8MGts/VaultExtension.jar";
    #   hash = "sha256-zGSz6ot1Zt0u29KXijBEhpc4+ryJ8CDK7JSvqCTcz1w=";
    # };
    # "plugins/Typewriter/extensions/WorldGuardExtension.jar" = pkgs.fetchurl {
    #   # WorldGuard IS installed here -- this one would actually work if
    #   # you want it, just not requested. Uncomment to enable.
    #   url = "https://cdn.modrinth.com/data/Vm7B3ymm/versions/NWX8MGts/WorldGuardExtension.jar";
    #   hash = "sha256-yCBw6DBWkNcfKyjIe538tgW9HHrTz3gttAKwR0znuWo=";
    # };

    # Bedrock-client cross-play proxy -- lets Bedrock/console/mobile
    # players join this Java server directly, no separate proxy needed.
    # "Spigot" build is the correct/only plugin-mode jar (Geyser doesn't
    # ship a separately-named Paper build, unlike BlueMap) -- runs fine
    # under Paper. Opens its own listener (default UDP 19132, same port
    # number as the Java side by default via port-remapping) -- add a
    # ports.nix entry if you want it reachable from outside this host.
    "plugins/Geyser-Spigot.jar" = pkgs.fetchurl {
      url = "https://cdn.modrinth.com/data/wKkoqHrH/versions/tQFyivtA/Geyser-Spigot.jar";
      hash = "sha256-efNudSvfb7na79Nat1OHu2ce+U829a7eNraXpOFLsS8=";
    };
  };
}
