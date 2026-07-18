{ ... }:

# &desc: "The actual autostart jobs for this machine -- data only, no logic."

# Real values -- schema + the actual unit-building logic live in
# ../../modules/system/autostart/. Data only, same reasoning as every
# config/<category>/<name>.nix file. See glossar/system/autostart.nix
# for a fully-annotated example entry.
#
# Ported straight from the old ~/Projects/Autostart (smg) manifest.json:
# only its 6 Casket vault-unlock jobs, nothing else. Every other old job
# (every self-hosted service restart, PortManager, QBitTorrentNox,
# FileBrowser) is already superseded by its own native NixOS module
# (config.vars.selfHosted.* autoStart, config.vars.ports) -- see this
# module's own docs/architecture.md. JellyfinMpvShim/RemoteAccess aren't
# here either -- both need the real logged-in session, out of scope for
# this root/boot-time engine by design.
#
# The keyfile PIN below is piped in plaintext, verbatim from the old
# manifest -- known, deliberately not fixed here (no secret data in the
# .img files themselves, just a known-insecure prompt bypass; a real
# fix is a separate task, not blocking this port). `sudo`/the outer
# `bash -c '...'` wrapper from the old command are dropped -- every job
# here already runs as root inside its own real bash script, so both
# were pure dead weight. No execRestart -- only execStart/execStop are
# used. execStop runs `cas <name> close` for each vault: with
# Type=oneshot + RemainAfterExit=true (see ../../modules/system/autostart/autostart.nix),
# systemd invokes ExecStop when the unit stops -- which includes normal
# shutdown/reboot ordering, before the generic filesystem unmount stage
# -- so every vault gets a clean LUKS close instead of relying purely on
# that generic unmount. This can't help against an actual power cut
# (no graceful shutdown happens at all then); LUKS mappers are in-kernel
# state anyway and never survive any reboot regardless, and `cas open`
# already tolerates a stale mapper/mountpoint left behind either way.
{
  config.vars.autostart = {
    enabled = true;

    jobs = {
      vaults = {
        execStart.cmd = ''
          cd /home/herauxvalle/Images || exit 1
          printf %s "314159265" | cas Vaults open --keyfile /run/media/herauxvalle/VirtualKeys/vaults/vaults.key --no-log
        '';
        execStop.cmd = ''
          cd /home/herauxvalle/Images || exit 1
          cas Vaults close --no-log
        '';
      };

      davinci = {
        execStart.cmd = ''
          cd /home/herauxvalle/Images || exit 1
          printf %s "314159265" | cas Davinci open --keyfile /run/media/herauxvalle/VirtualKeys/vaults/Davinci.key --no-log
        '';
        execStop.cmd = ''
          cd /home/herauxvalle/Images || exit 1
          cas Davinci close --no-log
        '';
      };

      media = {
        execStart.cmd = ''
          cd /home/herauxvalle/Images || exit 1
          printf %s "314159265" | cas Media open --keyfile /run/media/herauxvalle/VirtualKeys/vaults/Media.key --no-log
        '';
        execStop.cmd = ''
          cd /home/herauxvalle/Images || exit 1
          cas Media close --no-log
        '';
      };

      modrinth = {
        execStart.cmd = ''
          cd /home/herauxvalle/Images || exit 1
          printf %s "314159265" | cas Modrinth open --keyfile /run/media/herauxvalle/VirtualKeys/vaults/Modrinth.key --no-log
        '';
        execStop.cmd = ''
          cd /home/herauxvalle/Images || exit 1
          cas Modrinth close --no-log
        '';
      };

      tor = {
        execStart.cmd = ''
          cd /home/herauxvalle/Images || exit 1
          printf %s "314159265" | cas Tor open --keyfile /run/media/herauxvalle/VirtualKeys/vaults/Tor.key --no-log
        '';
        execStop.cmd = ''
          cd /home/herauxvalle/Images || exit 1
          cas Tor close --no-log
        '';
      };

      selfHosted = {
        execStart.cmd = ''
          cd /home/herauxvalle/Images || exit 1
          printf %s "314159265" | cas SelfHosted open --keyfile /run/media/herauxvalle/VirtualKeys/vaults/SelfHosted.key --no-log
        '';
        execStop.cmd = ''
          cd /home/herauxvalle/Images || exit 1
          cas SelfHosted close --no-log
        '';
      };
    };
  };
}
