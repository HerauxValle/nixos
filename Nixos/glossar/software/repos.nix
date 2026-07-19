# &desc: "Commented example reference for config.vars.packages.repos -- declarative git push-target registry (existing local dirs -> remotes, squash/history push), companion to repos.nix + gitctl."

{ ... }:

# ==========================================================================
# EXAMPLES -- every config.vars.packages.repos option, all commented out.
# Same shape as glossar/software/venvs.nix, scoped to one module. Schema:
# modules/packages/repos/default.nix. Logic that turns this into real
# pushes: modules/packages/repos/repos.nix + lib/ (the gitctl CLI,
# invoked as `pacnix github push`/`release`).
#
# This is a PUSH registry, not a clone tool -- `path` must already exist
# on disk. Nothing here ever clones, creates, or initializes a repo for
# you; `pacnix github push`/`release` fails loudly if `path` is missing
# instead of silently skipping it. Replaces
# ~/Scripts/Python/gitpushall.py's hardcoded REMOTES/SUBTREES/
# GITHUB_REPOS dicts with the same shape, declared here instead.
#
# NOT imported anywhere -- never evaluated, purely a copy-paste
# reference. Copy a block (or a line out of one) into
# config/software/environment/repos.nix and uncomment it there to
# actually declare it.
# ==========================================================================

{
  # config.vars.packages.repos = {

  #   # --- globals -------------------------------------------------------
  #   commitUserName = "you";                # default: config.vars.identity.username
  #   commitUserEmail = "you@example.com";   # default: config.vars.identity.gitCommitEmail
  #   # Stamped via `git -c user.name=... -c user.email=...` on every push
  #   # commit gitctl makes -- never written to any persistent gitconfig.

  #   repos = {

  #     # --- every field, one repo with both push modes --------------------
  #     # (mirrors gitpushall.py's actual dual-remote Dotfiles setup: real
  #     # history to one remote, a squashed snapshot to another)
  #     dotfiles = {
  #       path = "~/Dotfiles"; # must already exist -- never cloned/created
  #       excludeFiles = [ "Claude/Global/config.json" ]; # `git update-index --assume-unchanged`, history-mode remotes only
  #       excludePaths = [ ]; # stripped from the snapshot before committing, squash-mode remotes only
  #       githubRepo = null;  # "owner/repo" slug -- only needed for `pacnix github release`; null = release automation unavailable
  #       remotes = {
  #         origin = {
  #           url = "git@github.com:someuser/Dotfiles.git";
  #           mode = "squash"; # isolated tmp-repo snapshot, one commit, force-push -- path's own .git/history untouched
  #         };
  #         history = {
  #           url = "git@github.com:someuser/history.git";
  #           mode = "history"; # pushes path's REAL commits -- path must already be a real git repo; stages+commits, rebases, pushes (no force)
  #         };
  #       };
  #     };

  #     # --- minimal repo -- one remote, squash push, no release ----------
  #     scratch = {
  #       path = "~/Projects/scratch";
  #       remotes = {
  #         origin = {
  #           url = "git@github.com:someuser/scratch.git";
  #           mode = "squash";
  #         };
  #       };
  #     };

  #   };

  # };

  # --- `pacnix github push` pushes every declared repo (or just the
  # names you pass); `pacnix github release <name> <tag> [changelog]`
  # squash-pushes + tags + optionally creates a GitHub Release (needs
  # githubRepo here + a token from `secrets github add token`);
  # `pacnix github release rm <name> <tag>` deletes both. Nothing here
  # runs on a plain rebuild -- pushing only happens when you run one of
  # these yourself. See modules/packages/repos/lib/*.sh for the exact
  # safety model (no --force in history mode; squash mode force-pushes
  # an isolated snapshot, never path's own .git).
}
