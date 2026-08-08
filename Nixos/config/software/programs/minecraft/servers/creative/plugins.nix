# &desc: "Creative server's plugin jars -- Multiverse (worlds/nether-end linking), BlueMap, and the building-tool stack (FAWE/WorldGuard/Axiom/etc)."

{ pkgs, ... }:

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

    # REMOVED: Arceon -- your mirror link's file self-identified as
    # sourced from black-minecraft.com (a plugin piracy mirror), and
    # the jar refused to run with an internal "re-download from the
    # official site" error. Not reinstalling this from that source;
    # get me a legitimate link (your own Patreon download) if you
    # still want it.
    #
    # SKIPPED: ezEdits (Patreon/Discord-supporter gated, no public URL
    # -- you said skip), Schematic Brush Reborn 2 (SpigotMC direct
    # download is behind a Cloudflare bot-challenge, couldn't fetch it
    # programmatically -- get me a direct file/URL if you still want it).
  };
}
