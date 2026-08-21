# &desc: "Live-install ISO overrides -- generic dotted-path override list forcing off disk/service-specific settings, plus the embedded redacted flake. Only imported by nixosConfigurations.herauxvalle-iso, never the real machine."

{ lib, ... }:

# Reference-only relative to the real machine: not imported by
# configuration.nix, only by nixosConfigurations.herauxvalle-iso in
# flake.nix -- see that file. One generic mechanism instead of scattered
# one-off `lib.mkForce` lines: every value the ISO needs different from
# the real machine lives in `overrides` below as a dotted option path,
# and gets walked into a real forced override by the fold underneath.
# Works for both config.vars.* options and raw NixOS options uniformly.
{
  config = lib.mkMerge [
    (
      let
        overrides = {
          # Self-hosted services -- each has its own real enable switch
          # (config/self-hosted/<name>.nix), all genuinely `enabled = true`
          # on the real machine. Forced off here rather than reset in
          # Nixos/config/github/replacements.nix, since that mechanism is
          # for the GitHub-published copy's security posture, not the
          # ISO's size specifically -- a stranger building the full flake
          # normally should still get what's actually committed.
          "vars.services.selfHosted.ollama.enabled" = false;
          "vars.services.selfHosted.comfyui.enabled" = false;
          "vars.services.selfHosted.immich.enabled" = false;
          "vars.services.selfHosted.jellyfin.enabled" = false;
          "vars.services.selfHosted.stash.enabled" = false;
          "vars.services.selfHosted.openwebui.enabled" = false;
          "vars.services.selfHosted.searxng.enabled" = false;
          "vars.services.selfHosted.filebrowser.enabled" = false;
          "vars.services.selfHosted.qbittorrent.enabled" = false;
          "vars.services.selfHosted.odysseus.enabled" = false;

          "vars.packages.programs.steam.enable" = false;

          "vars.boot.usbRequired.enable" = false;
          "vars.security.sudoKeyfile.enable" = false;
          "vars.system.mountpoints.enabled" = false; # single master switch

          # installation-cd-minimal.nix force-disables fontconfig at
          # mkOverride 500 to save space, which silently drops
          # modules/desktop/theming.nix's fonts.packages (nerd-fonts,
          # for MyBar's icon glyphs) from the closure entirely --
          # confirmed absent from a real built ISO's squashfs. Re-enable
          # it so MyBar doesn't render tofu boxes on the live session.
          "fonts.fontconfig.enable" = true;

          # Switches modules/packages/packages/main.nix's ~100-entry list
          # into allowlist mode -- nothing from it ships unless a package
          # explicitly opts in with `builtIn = true;` (see that module's
          # per-package option). Login/session (SilentSDDM) is
          # deliberately NOT touched here -- runs exactly as it does on
          # the real machine. modules/boot/luks2/luks2.nix also reads
          # this directly (see that file) to skip its whole contribution
          # on the ISO, rather than being handled by an override here.
          "vars.isoBuild" = true;

          # boot.loader.grub targets this machine's specific disk,
          # meaningless on live media (the installer module's own
          # isoImage bootloader mechanism takes over instead).
          "boot.loader.grub.enable" = false;
          "boot.loader.timeout" = 10; # conflicts with modules/boot/grub/grub.nix's 5 otherwise -- confirmed via a real build attempt

          # The installer base module (installation-cd-minimal.nix)
          # enables ZFS support by default for broad hardware coverage.
          # Not needed (the real machine is btrfs+LUKS, not ZFS) and
          # this nixpkgs revision's zfs-kernel is marked broken for
          # kernel 7.1.3 -- confirmed via a real build attempt, not
          # assumed. Forcing it off avoids evaluating that package at
          # all rather than working around its brokenness.
          "boot.supportedFilesystems.zfs" = false;
        };
      in
      lib.foldl' lib.recursiveUpdate { } (
        lib.mapAttrsToList (
          path: value: lib.setAttrByPath (lib.splitString "." path) (lib.mkForce value)
        ) overrides
      )
    )

    # The exact redacted clone `pacnix release` builds this ISO from
    # gets embedded here at /dotfiles, so `nixos-install --flake
    # /dotfiles#<attr>` works fully offline inside the live
    # environment. Read from an env var (needs --impure), same pattern
    # as partitioning.nix's DISKO_TARGET_DEVICE/DISKO_ROOT_KEYFILE --
    # Scripts/Pacnix/cmd/release.sh sets this to the very clone it's
    # building from, so the ISO embeds a snapshot of itself, not a
    # separate copy.
    {
      isoImage.contents = [
        {
          source =
            let
              p = builtins.getEnv "ISO_DOTFILES_SOURCE";
            in
            if p == "" then
              throw ''
                ISO_DOTFILES_SOURCE is unset. Export it to the redacted
                flake checkout's path before building this ISO -- see
                Scripts/Pacnix/cmd/release.sh.
              ''
            else
              # builtins.getEnv only ever returns a plain string, which
              # the sandboxed builder can't see on disk -- `/. + p`
              # coerces it into a real Nix path, which forces it to be
              # copied into the store as a build input first (confirmed
              # needed via a real build attempt: without this, xorriso
              # failed with "Cannot determine attributes of source
              # file ... No such file or directory").
              /. + p;
          target = "/dotfiles";
        }
      ];
    }
  ];
}
