#!/usr/bin/env bash
cat <<'EOF'
usage: pacnix <command> [args]

  rebuild [--label <text>]
      Rebuild and switch to the new NixOS config (sudo nixos-rebuild
      switch). --label appends "-<text>" to the generation's normal
      date/version label in the GRUB menu -- only if given, otherwise
      the label is left as the plain default.

  validate
      Dry-run the rebuild (sudo nixos-rebuild dry-build) -- shows what
      would change, builds nothing, switches nothing.

  check
      Evaluate the flake for errors (nix flake check) -- fast, catches
      syntax/type mistakes without building anything.

  test-build
      Actually builds the full system closure (nix build, no switch) --
      catches real build failures without touching your running
      system.

  optimise
      Hardlinks duplicate files across the store to save space
      (nix-store --optimise). Pure dedup, deletes nothing. Prints
      store size before/after and Nix's own dedup-savings figure once
      it finishes -- no live spam during the run.

  orphaned
      Removes store paths unreferenced by any current or past
      generation (nix-collect-garbage, no --delete-older-than --
      doesn't touch generation history/rollback, only genuinely unused
      paths). Same before/after reporting as optimise.

  reload
      Runs the fish `reload` function (syncs fish/bash/nu/pwsh configs),
      `qsr` (relaunches MyBar), and `hyprctl reload`. Warns and does
      nothing if fish/qsr/hyprctl aren't found instead of half-running.
      Also reloads kitty's config (`kitty @ load-config`), but only from
      inside a kitty window -- silently skipped otherwise, best-effort.

  store <name>
      Finds nix store paths for a package name -- what's in the current
      system's closure right now, and separately, the highest version
      anywhere in /nix/store (may differ -- not garbage collected yet,
      etc.). e.g. pacnix store firefox

  packages
      Opens modules/packages/installed.nix in $EDITOR (falls back to
      nano if unset).

  modules [-q <term>] [-s] [-c] [-h] [-n] [-i] [-r]
      Lists available `programs.*` modules, alphabetically. Queries both
      home-manager and NixOS system modules by default -- -h or -n
      narrows to just one. No flags: just names, one per line (a name
      present in both sources is listed twice, once per source -- use
      -i to tell them apart).

      Backed by a local cache (~/.cache/pacnix/modules/) instead of
      hitting GitHub on every call -- the module list barely changes
      day to day, so there's no reason to spend one of GitHub's 60
      unauthenticated requests/hour on it every time. First run ever
      (no cache yet) errors and tells you to add -r; after that, plain
      calls are free and only -r talks to GitHub again.

      Output is colored regardless of flags (cyan [h] / magenta [n],
      green available / red not available, dim sha/urls) when stdout
      is a terminal; auto-off when piped/redirected, or set $NO_COLOR.
        -r          refetch from GitHub and overwrite the cache for
                    whichever source(s) are active, instead of reading
                    the cached copy. 1 request per active source (so 2
                    for the default combined mode, 1 for -hr or -nr
                    alone). Nothing else in this command ever refetches
                    on its own.
        -q <term>   fuzzy-search for a module (case-insensitive, not a
                    literal match -- exact, then substring, then a
                    Levenshtein/character-overlap score, same family of
                    passes as `run`'s own matcher) and report whether
                    something close is available, plus a few
                    alternates. Runs once per active source, so plain
                    `pacnix modules -q steam` checks both and reports
                    each separately. e.g. pacnix modules -q steam
        -s          show each module's GitHub link (source) instead of
                    just its name -- combine with -q to show the link
                    for just the match (-qs/-sq, either order).
        -c          curl the module's actual .nix source into the
                    terminal. With -q, fetches just that one match's
                    file (per active source). Without -q (bare -c, or
                    -sc with no query), it means every module in every
                    active source -- prompts for confirmation first
                    since that's 400+ requests.
        -h          home-manager only (nix-community/home-manager's
                    modules/programs) -- user-level `programs.*`
                    options (programs.fresh-editor, programs.fish, ...).
        -n          NixOS *system*-level `programs.*` options only
                    (nixpkgs' nixos/modules/programs), e.g.
                    programs.steam (see modules/packages/programs.nix).
                    Not exhaustive: some system `programs.*` options
                    live elsewhere in nixpkgs, or come from a separate
                    flake entirely (programs.hyprland,
                    programs.silentSDDM) -- "not available" under -n
                    only means "not in nixpkgs' own programs/ dir".
        -i          prefix each result with its source and blob sha,
                    "[h] - fish (2646268)". Free even on a full listing
                    of every module -- the sha is already part of the
                    directory listing fetched for the module list
                    itself, not a separate request. (A "last updated"
                    date was considered too -- dropped: GitHub's
                    unauthenticated REST API has no bulk endpoint for
                    that, only one commits-API call per file, which
                    would mean 600+ requests just to show it on a full
                    listing.)

  info [-o FIELD1,FIELD2,...] [-n] [-p]
      Exhaustive, machine-parsable system report -- 124 fields across
      15 categories: Packages, Store, Generations, Flake, System, Disk,
      Btrfs, NixConfig, GC, Hardware, Boot, Network, Security, Health,
      Session. Package provenance (system vs home-manager vs imperative
      vs full closure), store internals (derivations vs built outputs,
      fixed-output/network-fetched derivation count, top 5 largest
      packages, top 5 most-duplicated), exact flake pins, nix.conf and
      GC settings, btrfs allocation (not just df), systemd/journal
      health, network/firewall state, and more -- most of it well
      beyond what any single stock command gives you.
        -o LIST   select/order fields (like lsblk -o), `-o list` to
                  see all available fields, grouped, with descriptions
        -n        values only, no labels, one per line
        -p        KEY="value" pairs (like lsblk -P), eval-able
      A full run takes several seconds (multiple nix eval calls, a full
      closure walk, store-wide scans) -- `-o` a handful of cheap fields
      if you just need something fast.
      e.g. pacnix info -o STORE_SIZE,PKGS_SYSTEM -p

  help
      Show this message.
EOF
