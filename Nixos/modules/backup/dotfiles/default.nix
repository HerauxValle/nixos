{ config, lib, ... }:

# Logic that reads these lives in ./dotfiles.nix, imported below.
# remoteUrl has no sensible generic default (this specific repo's remote)
# -- its one real definition lives in Nixos/config/customized.nix.
{
  imports = [ ./dotfiles.nix ];

  options.vars.dotfilesBackup = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Master switch for the dotfiles GitHub backup.";
    };

    # `nixos-rebuild test` runs this exact same activation script for real
    # (immediately, unfiltered) -- it just skips persisting the bootloader
    # entry. Only `switch` and an actual boot into this generation are
    # genuinely permanent; `test` is a throwaway trial that would otherwise
    # still push a real, permanent tag. true = skip pushing on `test` runs.
    skipOnTest = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Skip pushing when NIXOS_ACTION=test (a throwaway trial run).";
    };

    dotfilesPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.homeDirectory}/Dotfiles";
      description = "Local path of the dotfiles repo being backed up.";
    };

    remoteUrl = lib.mkOption {
      type = lib.types.str;
      description = "Git remote the snapshot is pushed to.";
    };

    branch = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = "Branch pushed to on the remote.";
    };

    # `date`(1) format string for the tag pushed whenever something actually
    # changes -- change this to reformat it, nothing else needs touching.
    # Dashes for time, dots for date, one underscore between the two groups
    # -- git tags reject spaces/colons/brackets outright (not a length
    # limit), hence not the more obvious "hh:mm:ss | [DD-MM-YYYY]" layout.
    tagDateFormat = lib.mkOption {
      type = lib.types.str;
      default = "+%H-%M-%S_%d.%m.%Y";
      description = "date(1) format string for the tag pushed on each change.";
    };

    # Paths, relative to dotfilesPath, stripped from the snapshot before
    # committing -- never pushed anywhere.
    excludeFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "Claude/Global/config.json" "Shells/Fish/secrets.fish" ".envrc" ];
      description = "Paths (relative to dotfilesPath) stripped from the snapshot before committing.";
    };

    # Git identity stamped on the snapshot commit (passed via -c, never
    # written to root's own global gitconfig).
    commitUserName = lib.mkOption {
      type = lib.types.str;
      default = config.vars.username;
      description = "Git user.name stamped on the snapshot commit.";
    };

    commitUserEmail = lib.mkOption {
      type = lib.types.str;
      default = config.vars.gitCommitEmail;
      description = "Git user.email stamped on the snapshot commit.";
    };

    # true = reuse a persistent local clone across every activation and
    # skip the push entirely once nothing's actually changed -- lets git
    # send only the real diff, and skips the network completely on a
    # no-op rebuild. false = fresh throwaway repo + forced squash push
    # every time (no persistent history, always pushes).
    useRepoCache = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Reuse a persistent local clone across activations instead of a fresh throwaway repo each time.";
    };

    # Seconds to wait for a TCP connection before giving up, on every
    # network call this module makes (the push's SSH connection, and the
    # known_hosts HTTPS fetch). Without this, a genuinely dead connection
    # (DSL down, no route at all) doesn't fail fast -- it hangs for the
    # OS's own default TCP retry timeout, which can be 60-130+ seconds. A
    # dead connection can't be fixed by retrying anyway, so failing fast
    # here matters more than tolerating a slow-but-working one.
    connectTimeoutSeconds = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "TCP connect timeout for every network call this module makes.";
    };

    # How much this module prints -- doesn't change what it actually does
    # (push/recovery behavior is identical either way), only output:
    #   "normal" -- everything: success message, notes, and on failure the
    #               full diagnostic including git's real error text.
    #   "quiet"  -- no success message/notes; failures still show fully,
    #               just without git's raw error text.
    #   "silent" -- nothing at all, ever, success or failure. NixOS's own
    #               generic "Activation script snippet failed" line still
    #               shows on a real failure (printed by the activation
    #               framework itself, not this module), but none of this
    #               module's own output does.
    logLevel = lib.mkOption {
      type = lib.types.str;
      default = "normal";
      description = "How much this module prints: \"normal\", \"quiet\", or \"silent\".";
    };

    # Deploy key algorithm. No real reason to change this, but it's a
    # genuine independent choice (unlike keyComment, which is derived,
    # not chosen, and lives with the rest of the logic).
    keyType = lib.mkOption {
      type = lib.types.str;
      default = "ed25519";
      description = "Deploy key algorithm.";
    };

    # ANSI color codes used in the bordered blocks -- change these to
    # reskin the output. Empty string ("") for any of them disables that
    # color (still valid, just prints plain).
    colorRed = lib.mkOption {
      type = lib.types.str;
      default = ''\033[0;31m'';
      description = "ANSI color code for error output.";
    };
    colorYellow = lib.mkOption {
      type = lib.types.str;
      default = ''\033[0;33m'';
      description = "ANSI color code for warning/note output.";
    };
    colorGreen = lib.mkOption {
      type = lib.types.str;
      default = ''\033[0;32m'';
      description = "ANSI color code for success output.";
    };
    colorReset = lib.mkOption {
      type = lib.types.str;
      default = ''\033[0m'';
      description = "ANSI reset code.";
    };

    # Printed at the top/bottom of every warning/error/success block so
    # they're unmistakably one unit and clearly attributed to this module
    # amid the rest of the rebuild output.
    border = lib.mkOption {
      type = lib.types.str;
      default = "[dotfiles-backup] ============================================";
      description = "Border line printed around every warning/error/success block.";
    };

    # Below: plain facts too, not procedural logic -- "DO NOT TOUCH" in the
    # original file meant "these are derived/external facts, not personal
    # preference, so there's rarely a reason to edit them," not "don't
    # relocate this." The real logic (gitSshCommand's pkgs-dependent
    # construction, refreshKnownHosts, gitPush) stays in
    # modules/backup/dotfiles.nix.

    # Own subdirectory under the existing root-owned secrets convention
    # (see config/security/sudo-keyfile.nix, config/system/users.nix) so
    # this doesn't bloat the flat /etc/nixos-secrets/ directory.
    secretsDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.secretsBaseDir}/github";
      description = "Root-owned directory holding this module's deploy key/known_hosts/repo cache.";
    };

    # Derived from dotfilesPath's own last path component (not an
    # independent literal) so it always matches reality.
    keyComment = lib.mkOption {
      type = lib.types.str;
      default = "${baseNameOf config.vars.dotfilesBackup.dotfilesPath}-backup";
      description = "SSH key comment on the generated deploy key.";
    };

    # GitHub's own fixed API endpoint / error markers -- named here purely
    # for visibility rather than buried inline as string literals in the logic.
    githubMetaApiUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://api.github.com/meta";
      description = "GitHub's API endpoint for refreshing known_hosts.";
    };
    githubSecretScanErrorCode = lib.mkOption {
      type = lib.types.str;
      default = "GH013";
      description = "GitHub's push-rejection code for a detected secret.";
    };
    hostKeyFailureMarker = lib.mkOption {
      type = lib.types.str;
      default = "Host key verification failed";
      description = "OpenSSH's fixed wording for a host-key mismatch.";
    };

    # OpenSSH/curl's own fixed wording for "no network route at all" --
    # matched to short-circuit straight to a plain network-failure message
    # instead of working through the other recovery paths (host-key
    # refresh, force retry, GH013 rewrite), none of which can fix a dead
    # connection and would just waste time repeating doomed network calls.
    networkFailureMarker = lib.mkOption {
      type = lib.types.str;
      default = "Could not resolve hostname|Connection timed out|Network is unreachable|No route to host";
      description = "OpenSSH/curl's fixed wording for \"no network route at all\".";
    };

    # This repo's own deploy key -- read-only for anyone but root, scoped to
    # pushing this one remote. Rotate any time by hand with `secrets
    # dotfiles` (Scripts/Secrets/cmd/dotfiles.sh); the activation script
    # also generates one itself if none exists yet (a safety net, same idea
    # as users.nix's password-hash fallback), it just never rotates an
    # existing one on its own -- rotation is exclusively a `secrets
    # dotfiles` action.
    keyFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.dotfilesBackup.secretsDir}/dotfiles-backup";
      description = "Deploy key path.";
    };

    # Generated once (if missing), like the deploy key -- not refetched on
    # every activation, since that'd be a whole extra network round-trip
    # (separate DNS+TLS handshake to a different host from the push itself)
    # for no benefit in the common case where it's already correct. If
    # GitHub ever rotates their host key, the push-failure recovery in the
    # logic detects that specific failure and refreshes it automatically.
    knownHostsFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.dotfilesBackup.secretsDir}/known_hosts";
      description = "known_hosts path used for the push's SSH connection.";
    };

    repoCache = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.dotfilesBackup.secretsDir}/repo-cache";
      description = "Persistent local clone path, used when useRepoCache is true.";
    };
  };
}
