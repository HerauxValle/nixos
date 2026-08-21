# &desc: "Commented example reference for config.vars.services.selfHosted.immich -- copy/paste into config/self-hosted/immich.nix, wraps nixpkgs services.immich, companion to info.md."

{ ... }:

# =========================================================================
# EXAMPLES -- every config.vars.services.selfHosted.immich option, all commented
# out. Same shape as glossar/main/variables.nix, scoped to one service.
# Schema: modules/services/self-hosted/immich/default.nix. Real values on
# this machine: config/self-hosted/immich.nix. Full reference (systemd
# units, workflows, "why" for every mechanism below):
# modules/services/self-hosted/immich/info.md.
#
# Unlike every other service here, Immich wraps nixpkgs' own mature
# services.immich module instead of being built from scratch -- no
# dataDir/storage/teardownPaths/version/hash exist on this schema at all.
#
# NOT imported anywhere -- never evaluated, purely a copy-paste reference.
# Copy a block (or a line out of one) into config/self-hosted/immich.nix
# and uncomment it there to actually set it. Terse, ini-style companion to
# that service's info.md -- regenerate by hand alongside it, nothing keeps
# either in sync automatically.
# =========================================================================

{
  # config.vars.services.selfHosted.immich = {

  #   # --- master switch --------------------------------------------------
  #   # true = services.immich.enable (+ .database.enable/.redis.enable)
  #   # wired on, live units exist. false = none of it exists. Real data
  #   # (mediaLocation, the Postgres database) is never touched either
  #   # way -- there's no teardownPaths mechanism here at all, see info.md.
  #   enabled = false;

  #   # false = exists, systemctl start-able (systemctl start immich-server),
  #   # but not on boot/rebuild. Overrides the wrapped module's own
  #   # hardcoded wantedBy via lib.mkForce -- see immich.nix.
  #   autoStart = true;

  #   # --- real photo/video storage root -- no dataDir/storage list here ---
  #   # passed straight to services.immich.mediaLocation. Required, no
  #   # generic default.
  #   mediaLocation = "${homeDirectory}/Images/Media/Cloud";

  #   # --- must already be a mountpoint before immich-server runs ----------
  #   requireMounts = [ "${homeDirectory}/Images/Media" ];

  #   # --- optional typed overrides -- real options on the wrapped module already --
  #   # null (default, both) = services.immich.host/.port's own defaults
  #   # (localhost:2283) apply untouched.
  #   host = null;
  #   port = null;

  #   # --- passed to services.immich.secretsFile -----------------------------
  #   # CAUTION: no "-" missing-file fallback the way this framework's own
  #   # environmentFile convention has elsewhere -- pointing this at a file
  #   # that doesn't exist yet is a hard unit-start failure. Only set once
  #   # the real file already exists (`secrets self-hosted immich`).
  #   environmentFile = null;

  #   # --- face recognition / smart search sidecar ----------------------------
  #   enableMachineLearning = true;

  #   # --- pass-through envs, same shape as every other service's environment --
  #   environment = {
  #     IMMICH_LOG_LEVEL = "verbose";
  #   };
  #   machineLearningEnvironment = {
  #     MACHINE_LEARNING_MODEL_TTL = "600";
  #   };

  # };
}
