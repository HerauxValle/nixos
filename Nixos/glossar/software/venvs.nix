{ ... }:

# ==========================================================================
# EXAMPLES -- every config.vars.venvs option, all commented out.
# Same shape as glossar/main/variables.nix, scoped to one module. Schema:
# modules/packages/venvs/default.nix. Logic that turns this into real
# venvs + direnv wiring: modules/packages/venvs/venv.nix.
#
# A venv registry/builder, not just a static list -- packages is the
# only required field per venv, since a venv with no path override still
# resolves against the global basePath, and a venv with no activation
# still gets built and reachable via `venvctl activate`.
#
# `path`, when omitted, resolves to `${basePath}/<name>` -- there is no
# static string to hand back for that at eval time in this file, since
# resolution happens against config.vars.homeDirectory in venv.nix, not
# here. Same reasoning as mountpoints' device.<key>.path: this file is
# never imported, so nothing here is live config to reference anyway.
#
# NOT imported anywhere -- never evaluated, purely a copy-paste
# reference. Copy a block (or a line out of one) into
# config/software/venvs.nix and uncomment it there to actually set
# it.
# ==========================================================================

{
  # config.vars.venvs = {

  #   # --- globals -----------------------------------------------------
  #   logLevel = "error"; # debug/silent/error -- see venv.nix lib/manage/log.sh
  #   basePath = "~/.impure/python-venvs/nix-declared"; # default parent for venvs w/o their own `path`

  #   venvs = {

  #     # --- every field, one venv --------------------------------------
  #     scraper = {
  #       path = null;          # null = derive as basePath/<name>; or set an override e.g. "~/dev/scraper/.venv"
  #       python = "python311"; # nixpkgs attribute name for the interpreter
  #       packages = {
  #         requests = "2.32.3";      # pinned -- rebuild reinstalls if this version changes
  #         beautifulsoup4 = "latest"; # floating -- installed once, only `venvctl update` bumps it
  #       };
  #       activation = {
  #         onEntry = true; # false = build it, but never auto-activate via direnv
  #         paths = {
  #           # omit entirely (with onEntry = true) to fall back to the
  #           # implicit single trigger at the venv's own resolved path.
  #           # declaring even one path here fully replaces that default.
  #           "~/dev/scraper" = "recursive"; # recursive/flat, same semantics as vars.shells
  #         };
  #       };
  #       lockfile = false; # true = pip-freeze into Dotfiles/Python/locks/nix-managed/<name>/*.lock on build/update
  #     };

  #     # --- minimal venv -- build it, no auto-activation, no lock -------
  #     scratch = {
  #       packages = {
  #         ipython = "latest";
  #       };
  #     };

  #   };

  # };

  # --- a path can't be both a vars.shells entry and a venv activation
  # path -- venv.nix asserts this at eval time and fails the build with
  # the exact colliding path(s) if you try. See
  # modules/packages/venvs/docs/DECISIONS.md.
}
