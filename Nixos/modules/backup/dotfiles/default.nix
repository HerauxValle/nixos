# &desc: "Dotfiles GitHub backup schema -- opt-in master switch, skipOnTest to avoid pushing on test runs, remote URL and branch config."

{ config, lib, ... }:

# Logic that reads these lives in ./lib/, imported below.
# remoteUrl has no sensible generic default (this specific repo's remote)
# -- its one real definition lives in Nixos/config/config.nix.
{
  imports = [ ./lib ];

  options.vars.backup.dotfilesBackup = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Master switch for the dotfiles GitHub backup. Opt-in: a stranger cloning this repo shouldn't silently start generating a deploy key and pushing commits to whatever remoteUrl they configure -- this machine's own real value lives in Nixos/config/config.nix.";
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
      default = "${config.vars.identity.homeDirectory}/Dotfiles";
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
    # committing -- never pushed anywhere. No sensible generic default
    # (this machine's specific sensitive paths) -- its one real definition
    # lives in Nixos/config/github/exclusions.nix.
    #
    # Gitignore-style patterns are supported, not just exact paths: an
    # entry with none of *, ?, [ is a plain literal path (matched exactly
    # as before -- existing entries keep their exact prior behavior with
    # no change), one containing any of those is matched with Python's
    # fnmatch against every path under dotfilesPath -- the same engine
    # git-filter-repo's own glob matching uses internally, so a pattern
    # excludes identically from the live snapshot and from the
    # (retroactive) history scrub. See lib/scripts/exclude.py's own top
    # comment for the one real difference from an actual .gitignore
    # (fnmatch's `*` already crosses `/`, so there's no need for `**`).
    excludeFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Paths (relative to dotfilesPath) stripped from the snapshot before committing. Supports gitignore-style glob patterns (*, ?, [seq]), not just exact paths.";
    };

    # Git identity stamped on the snapshot commit (passed via -c, never
    # written to root's own global gitconfig).
    commitUserName = lib.mkOption {
      type = lib.types.str;
      default = config.vars.identity.username;
      description = "Git user.name stamped on the snapshot commit.";
    };

    commitUserEmail = lib.mkOption {
      type = lib.types.str;
      default = config.vars.identity.gitCommitEmail;
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
      default = "${config.vars.identity.secretsBaseDir}/github";
      description = "Root-owned directory holding this module's deploy key/known_hosts/repo cache.";
    };

    # Derived from dotfilesPath's own last path component (not an
    # independent literal) so it always matches reality.
    keyComment = lib.mkOption {
      type = lib.types.str;
      default = "${baseNameOf config.vars.backup.dotfilesBackup.dotfilesPath}-backup";
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
      default = "${config.vars.backup.dotfilesBackup.secretsDir}/dotfiles-backup";
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
      default = "${config.vars.backup.dotfilesBackup.secretsDir}/known_hosts";
      description = "known_hosts path used for the push's SSH connection.";
    };

    repoCache = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.backup.dotfilesBackup.secretsDir}/repo-cache";
      description = "Persistent local clone path, used when useRepoCache is true.";
    };

    # true = whenever excludeFiles OR redactValues changes (an entry added,
    # removed, or edited), rewrite the ENTIRE local history to strip/redact
    # every listed path from every past commit too, then force-push that
    # rewritten history -- not just apply the new lists going forward.
    # Without this, changing either list only protects future commits;
    # anything already committed under the old lists stays exposed in every
    # earlier commit, both in repoCache and on the already-pushed remote,
    # forever. Only meaningful when useRepoCache is true -- the non-cache
    # mode never keeps history across activations, so there's nothing to
    # retroactively scrub.
    scrubHistoryOnExcludeChange = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Rewrite and force-push the full local history (not just future commits) whenever excludeFiles or redactValues changes.";
    };

    # Records a hash of excludeFiles+redactValues after the last scrub, so
    # a scrub only runs when either list actually changed -- not on every
    # activation regardless.
    excludeHashFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.backup.dotfilesBackup.secretsDir}/exclude-hash";
      description = "Stores a hash of excludeFiles+redactValues from the last scrub, to detect when either changes.";
    };

    # Files that stay backed up in full, but with one specific value inside
    # them replaced by asterisks (same length) instead of the whole file
    # being dropped -- for a file you need synced (real, necessary config)
    # that also happens to contain one sensitive literal (a MAC address, an
    # email) mixed in with everything else. No sensible generic default
    # (this machine's specific sensitive values) -- its one real definition
    # lives in Nixos/config/github/exclusions.nix.
    #
    # `key` is a dotted path resolved against the top-level `config` (not
    # `config.vars` specifically) -- e.g. "networking.interfaces.enp3s0.macAddress"
    # or "vars.identity.gitCommitEmail". Deliberately a plain string, not a literal
    # Nix expression reaching into another module -- this module never
    # needs to know networking.nix's structure at eval time, and nothing
    # sensitive needs its own dedicated options.vars.* entry just to
    # qualify for redaction; anything already exposed as a real option
    # (built-in or custom) works as-is.
    redactValues = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          file = lib.mkOption {
            type = lib.types.str;
            description = "Path, relative to dotfilesPath, containing the value to redact.";
          };
          key = lib.mkOption {
            type = lib.types.str;
            description = "Dotted path into config (e.g. \"vars.identity.gitCommitEmail\") whose value gets redacted in `file`.";
          };
          # Optional scope-down for a value that appears on more than one
          # line of `file` when only a specific occurrence is meant --
          # same idea and same type as replaceValues' own `line` below,
          # see that option's description for the full reasoning. Only
          # scopes the live per-activation redaction/preflight check;
          # the history scrub's --replace-text still matches this value
          # anywhere in any blob across all of history, same as an
          # unscoped entry always did (git-filter-repo has no concept of
          # "this file's line N" for a rewrite spanning every past
          # commit).
          line = lib.mkOption {
            type = lib.types.nullOr (lib.types.either lib.types.int (lib.types.listOf lib.types.int));
            default = null;
            description = "Restrict redaction to one specific 1-indexed line number in `file` (or a list of them), instead of every line that contains the value. null (default) keeps the prior unscoped behavior.";
          };
        };
      });
      description = "Files kept in the backup, with one config-derived value inside them replaced by asterisks.";
    };

    # Files kept in the backup in full, but with one exact literal string
    # inside them swapped for another literal string you choose -- for a
    # value that isn't sensitive so much as personal (a real username, a
    # real hostname) that you want to appear as a plausible placeholder in
    # the published copy instead of either the real value or asterisks.
    # The replacement drops straight in and the line is never commented
    # out, unlike redactValues -- so the published file has to already be
    # valid with `replaceWith` substituted in place of whatever `find`/`key`
    # resolves to, same shape and all. This is also the reason redactValues
    # is the wrong tool for anything that's a *required* option (no
    # default): commenting the line out there leaves the option undefined,
    # which is a hard eval error for anyone actually building the published
    # copy -- confirmed live against modules/backup/dotfiles/dotfiles.nix's
    # own redactValues entries before gitCommitEmail/usbSerialShort moved
    # here. `replaceWith` always keeps the option defined.
    #
    # Give exactly one of `find` (a literal you type out by hand -- the
    # whole construct you mean to touch, e.g. the entire `username = "...";`
    # line, not just the bare value: an unscoped bare value would also
    # match any unrelated occurrence of that same string elsewhere in the
    # file -- pin it to one exact spot with `line` below instead of typing
    # out the whole surrounding construct by hand, or anywhere else in the
    # repo during the history scrub, which `line` does NOT reach, see that
    # option's own description) or `key` (a dotted path into config, e.g.
    # "vars.identity.gitCommitEmail" -- resolved to its CURRENT value at eval time
    # instead of typed out by hand, so it can't drift out of sync with the
    # real value the way a hand-copied `find` could). Unlike redactValues'
    # same-shaped `key` lookup, a `key` here that fails to resolve is NOT a
    # hard eval error -- see resolveReplaceEntry in ./dotfiles.nix -- it's
    # reported as a runtime warning and that one entry is just skipped,
    # since a stale/renamed key is a much likelier and much less
    # catastrophic failure mode for a "replace" than for a "redact".
    replaceValues = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          file = lib.mkOption {
            type = lib.types.str;
            description = "Path, relative to dotfilesPath, containing the text to replace.";
          };
          find = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Exact literal text to find in `file`. Give exactly one of `find`/`key`.";
          };
          key = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Dotted path into config, resolved to its current value and used as the text to find. Give exactly one of `find`/`key`.";
          };
          replaceWith = lib.mkOption {
            type = lib.types.str;
            description = "Literal text substituted in place of whatever `find`/`key` resolves to.";
          };
          # A single int or a list of ints, both accepted by the same
          # option -- `enable = true;` is a legitimate example: it's a
          # substring of `usbRequired.enable = true;`/`sudoKeyfile.enable
          # = true;` elsewhere in the same config.nix, so an unscoped
          # `find` there would also corrupt those, or (if applied after
          # them) find nothing left to match and misreport itself as
          # stale. Pointing `line` at the one real line sidesteps that
          # without having to hand-write the whole surrounding block as
          # `find` (which breaks the moment the file's formatting/
          # indentation shifts, the actual failure mode that motivated
          # this option). Only scopes the live per-activation replace/
          # preflight check, not the history scrub -- see redactValues'
          # own `line` option above for why.
          line = lib.mkOption {
            type = lib.types.nullOr (lib.types.either lib.types.int (lib.types.listOf lib.types.int));
            default = null;
            description = "Restrict replacement to one specific 1-indexed line number in `file` (or a list of them), instead of every occurrence in the whole file. null (default) keeps the prior unscoped behavior.";
          };
        };
      });
      default = [ ];
      description = "Files kept in the backup with one exact literal string swapped for another literal string of your choosing.";
    };
  };

  config.assertions = [
    {
      assertion = builtins.all (r: (r.find == null) != (r.key == null)) config.vars.backup.dotfilesBackup.replaceValues;
      message = "modules/backup/dotfiles: every replaceValues entry needs exactly one of `find`/`key`, not both and not neither.";
    }
  ];
}
