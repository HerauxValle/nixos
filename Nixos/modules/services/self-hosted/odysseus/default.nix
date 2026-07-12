{ lib, config, ... }:

# Schema only -- logic lives in ./odysseus.nix (wiring) and ./lib/
# (fhs.nix, update.nix). Ported from ~/Scripts/Self-hosted/Odysseus/,
# read as a behavioral reference only -- but unlike every already-ported
# service, that old main.sh was a bare nohup+PID-file script, not part
# of the modular configuration/variables/ framework the 8 already-
# migrated services had. The real, authoritative source for how Odysseus
# itself actually works is its own upstream repo
# (github.com/pewdiepie-archdaemon/odysseus, real, confirmed via `git
# remote -v` against the actual checkout already recovered into the
# vault -- not guessed), read directly (README.md, setup.py,
# odysseus-ui.service, .env.example) before writing this module.
#
# Real shape: same as SearXNG, not OpenWebUI -- Odysseus has no pip
# package at all, it's a git-clone-pinned source tree (confirmed: no
# setuptools/build-system in pyproject.toml, just pytest config) run
# directly via `uvicorn app:app` from its own checkout root, the same
# way upstream's own odysseus-ui.service template does it. Real
# difference from SearXNG: Odysseus's own application code (setup.py,
# core/database.py, and presumably more throughout core/routes/src/)
# computes its data paths as plain subdirectories of wherever the
# running script itself lives (BASE_DIR/data, BASE_DIR/.env via
# load_dotenv()'s default cwd-relative search) -- there's no env-var
# override for this the way SearXNG's SEARXNG_SETTINGS_PATH lets Nix
# point settings.yml wherever it wants. Consequence: the real vault-
# backed data has to be symlinked *into* srcDir itself (see
# odysseus.nix's dataLinkScript, same rm-rf-then-symlink idiom as
# SearXNG's own themeLinkScript), not into a separate plain dataDir --
# so this schema has no dataDir option at all, unlike every other
# service (Immich is the only other one with no dataDir, for a
# different, unrelated reason -- see its own default.nix).
{
  imports = [ ./odysseus.nix ];

  options.vars.selfHosted.odysseus = {
    enabled = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Master switch. true = the live service and its actions run
        exactly as declared. false = treated as if this service doesn't
        exist -- no systemd units at all, and venvDir (the only thing
        this service has that's safe to auto-remove) gets torn down on
        the next rebuild. srcDir is never auto-removed either way (same
        already-accepted limitation as SearXNG's own srcDir -- see
        mk-teardown-activation-script.nix, which only knows about
        dataDir/venvDir), and storage-backed real data (the vault) is
        never touched by this regardless. See ../docs/architecture.md.
      '';
    };

    # Both live under ~/.impure/, not the vault -- real, git/pip-managed
    # files on disk Nix cannot fully account for, kept apart from the
    # real vault-backed data on purpose (same reasoning as every other
    # venv-based service -- see architecture.md's "~/.impure/" section).
    # srcDir is a sibling of venvDir rather than nested inside it
    # deliberately -- mkVenvInstallScript wipes venvDir entirely on every
    # lock-hash change, which would force a needless git-reclone every
    # time if srcDir lived inside it (identical reasoning to SearXNG's
    # own srcDir/venvDir split).
    venvDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.homeDirectory}/.impure/python-venvs/self-hosted/odysseus";
      description = "Where the Python venv lives -- disposable, regenerated from requirementsLock automatically by preStart's venvEnsureScript whenever the lock's hash changes.";
    };

    srcDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.vars.homeDirectory}/.impure/python-venvs/self-hosted/odysseus-src";
      description = "Where the pewdiepie-archdaemon/odysseus git checkout lives, pinned to coreRev by preStart every start (a no-op once already at that rev). A fresh clone, deliberately not reusing the real checkout already sitting in the vault (~/Images/SelfHosted/Odysseus) -- that path stays real, vault-backed, storage-only from Nix's perspective (see storage below), matching this repo's own convention that impure git/pip-managed source never lives in the vault alongside real declared data.";
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the live service starts automatically on boot/rebuild (wantedBy multi-user.target).";
    };

    # str/port, not nullOr like SearXNG's -- uvicorn has no "leave as
    # whatever a config file already says" mechanism the way SearXNG's
    # settings.yml provides; --host/--port are always explicit CLI flags
    # on every invocation (confirmed directly in both the old main.sh and
    # upstream's own odysseus-ui.service template), so there's nothing
    # sensible for "don't touch" to mean here. Defaults match the real
    # values the old main.sh already used on this machine.
    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Bind address, passed as uvicorn's --host.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 7000;
      description = "Bind port, passed as uvicorn's --port. Matches upstream's own real default (confirmed in README.md/.env.example) and the old main.sh's real value.";
    };

    # Plain passthrough -- most of Odysseus's own config already lives in
    # the real .env file itself (see storage below, a single-file entry
    # symlinked into srcDir, exactly like SearXNG's settings.yml) and is
    # read directly by the app's own load_dotenv() call, not through
    # systemd's environment at all. This exists only for anything you
    # want to override on top of that without editing the real .env.
    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Environment variables for the live odysseus process, on top of whatever the real .env (see storage) already sets via its own load_dotenv() call.";
    };

    # Same shape as every other service's storage option, but consumed
    # differently by odysseus.nix's own dataLinkScript: src is relative
    # to srcDir here, not a plain dataDir (Odysseus has none -- see this
    # file's own top comment for why). Real config: data/logs/.env,
    # already real and vault-backed at ~/Images/SelfHosted/Odysseus/ from
    # a previous real install (89MB, including an already-set-up admin
    # account -- confirmed by inspecting that directory directly, not a
    # fresh install like Immich's mediaLocation turned out to be).
    storage = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          src = lib.mkOption {
            type = lib.types.str;
            description = "Path, relative to srcDir, that should be a symlink. Can point at a single file (e.g. \".env\"), not just a directory.";
          };
          dest = lib.mkOption {
            type = lib.types.str;
            description = "Absolute target the symlink points at.";
          };
        };
      });
      default = [ ];
      description = "Storage relocations, symlinked directly into srcDir by odysseus.nix's own dataLinkScript (not the generic dataDir-based L+ tmpfiles mechanism every dataDir-having service uses -- see this file's top comment for why).";
    };

    requireMounts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Paths that must already be mountpoints before this service (or any of its preStart) runs. See modules/services/self-hosted/self-hosted.nix's mkSelfHostedService.";
    };

    # No sensible generic default (there's no "right" revision) -- same
    # reasoning as SearXNG's own coreRev. Real value: the exact commit
    # the vault's already-recovered checkout was actually sitting at
    # (`git rev-parse HEAD`, confirmed clean -- no uncommitted changes),
    # not just "whatever HEAD happens to be" -- pins to what's actually
    # been running and is known to work with the recovered real data.
    coreRev = lib.mkOption {
      type = lib.types.str;
      description = "pewdiepie-archdaemon/odysseus git rev to pin. preStart clones srcDir if missing, then checks out this rev every start (no-op if already there).";
    };
  };
}
