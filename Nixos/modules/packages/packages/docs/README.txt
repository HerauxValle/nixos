packages/ — declarative package installation with optional
per-package version coexistence.

BASIC USE (no versioning)

  config.vars.environment.packages.pkgs.vivaldi = { };

Resolves to `pkgs.vivaldi`, unsuffixed, on PATH. Nothing else needed.

VERSIONED USE

  config.vars.environment.packages.pkgs.swift = {
    versions = {
      "latest" = "";
      "5.9.4"  = "nixpkgs-old-swift";
      "5.5.0"  = "b5aa0fb";
    };
    default = "latest";
  };

Each key in `versions` is a label of your choosing (doesn't have to be
a real version number). Each value is a "spec" string saying where
that label's build comes from:

  ""  or  "latest"     -> the package from the normal source, i.e.
                           `sources.pkgs.swift` (pure, fast, no extra
                           setup)

  a flake input name    -> resolved as
                           `(import inputs.<name> { inherit system; }).swift`
                           Requires the input to already be declared
                           in flake.nix, e.g.:
                             inputs.nixpkgs-old-swift.url =
                               "github:NixOS/nixpkgs/<commit>";
                           Pure, fast, no copy-pasting hashes at eval
                           time — the pin lives in flake.lock.

  anything else          -> treated as a raw commit hash or channel
                           string, e.g. "b5aa0fb" or
                           "26.11.20260629.b5aa0fb". Fetched on the fly
                           with `builtins.fetchTarball`. No flake.nix
                           edits needed, but also no lockfile pin, so
                           re-fetches can drift. Optionally carries a
                           "#<hash>" suffix that pins the fetch:

                             "26.11.20260629.b5aa0fb"
                               -> unpinned, impure. Needs
                                  `nixos-rebuild switch --impure` (or
                                  equivalent) to evaluate.

                             "26.11.20260629.b5aa0fb#<sha256>"
                               -> pinned, pure. No --impure needed.

                             "26.11.20260629.b5aa0fb#"
                               -> bare trailing "#". Fetched impurely,
                                  same as the unpinned case above (still
                                  needs --impure) -- but the fetch's real
                                  hash also gets reported cleanly after
                                  the build, see HASH DISCOVERY below.
                                  Used to find the hash to paste back in
                                  as "#<sha256>", without ever touching
                                  Nix's own error text.

                           A hash given after "#" is used exactly as
                           written and never independently checked by
                           this module -- if it's wrong, the build just
                           fails on it the normal way, same as any other
                           mispinned fetch. Only the unpinned case (no
                           "#" at all) prints a bordered `builtins.trace`
                           banner naming the package/label right before
                           Nix's own "requires a 'sha256' argument"
                           error, so it's easy to spot scrolling past a
                           full-system rebuild's noise.

HASH DISCOVERY (bare "#" specs)

A bare trailing "#" can't be resolved to a clean, custom-formatted hash
message from inside Nix itself -- nothing in the Nix expression language
can catch a builtin fetch's error and read the real hash back out of it
(confirmed: `builtins.trace` strips control bytes from its own
messages, so not even coloring the output is possible that way; and
`builtins.exec`, the one builtin that could shell out to compute it
directly, is gated behind the system-wide `nix.settings.
allow-unsafe-native-code-during-evaluation` daemon setting -- literally
named unsafe, and not scoped to just this feature).

So hash discovery happens after the build instead, as a normal,
unrestricted NixOS activation script:

  1. Every bare-"#" spec across all declared packages gets collected
     into a manifest (`{ name; version; spec; sourcePath; }` per entry,
     deduplicated), written to `/etc/packages-hash-manifest.json`.
  2. `system.activationScripts.packagesHashDiscovery` reads that
     manifest after the build completes (it can only run at all if the
     build already succeeded -- which for a bare-"#" spec means building
     with `--impure`), runs `nix hash path` on each entry's fetched
     store path, and prints:
       [Packages] Missing hash: <name> <version> <hash>  (spec '<spec>')
     Plain bash, so no purity restrictions -- full control over the
     output format, real colors if wanted, no Nix error noise at all.
  3. Copy the printed hash back into `packages.nix` after the "#" and
     rebuild -- now pinned and pure, no more `--impure` needed for that
     entry, and it drops out of the manifest.

No caching, no drift detection against a previous hash -- deliberately
kept simple. A "#<hash>" spec is trusted as-is and never re-verified;
only a bare "#" ever triggers discovery.

Every entry in `versions` gets built and exposed suffixed with its
label, e.g. `swift-5.9.4`, `swiftc-5.9.4` (every file in that build's
bin/, not just one hardcoded name). Whichever label is named in
`default` is *additionally* exposed two more ways: unsuffixed --
`swift`, `swiftc` -- so plain PATH lookups keep working, and suffixed
"-latest" -- `swift-latest`, `swiftc-latest` -- so it stays reachable
under a name that doesn't change later if `default` gets repointed at a
different label. `default` must be a key that actually exists in
`versions`; if it doesn't, evaluation fails with a clear error
(lib/validate.nix) instead of silently picking something. A real
version key literally named "latest" is also checked -- if present and
not itself the one named in `default`, it would collide with the
automatic "-latest" name, so evaluation fails with a clear error
instead of two derivations silently fighting over the same file.

Leaving `versions = { }` (the default) skips all of this and behaves
exactly like the basic, no-versioning case above.

CUSTOM ALIASES ("@<alias>" in a versions key)

A `versions` key may carry an optional "@<alias>" suffix, e.g.
"5.10.1@swift5". Doesn't change what gets fetched -- `versions.${key}`
is still looked up by the raw, full key -- and doesn't change the
normal "-<version>" suffixed exposure either, since that's built from
the part before "@" (so "swift-5.10.1" gets built exactly as it would
without the alias). All it adds is one extra, direct PATH name:
whichever single file in that build's bin/ is literally named like the
package (e.g. bin/swift, not every file the way suffixing covers all of
them) gets an additional plain symlink under the alias name -- "swift5"
runs the exact same binary as "swift-5.10.1".

`default` still names a raw key exactly as before -- if you want an
aliased key to also be `default`, name it in full, "@<alias>" included.

Alias names must be globally unique across every declared package, not
just within one -- two different packages (or two labels of the same
package) both claiming "swift5" would otherwise collide when building
environment.systemPackages. Checked with a single assertion in
main.nix, same pattern as lib/validate.nix's `default` check: a clear
eval-time error naming the exact duplicate(s) instead of a cryptic
file-collision failure later in the build.

WHY VERSION LABELS AREN'T ALWAYS ENOUGH

Two builds can report the same version number but behave differently
(e.g. swift 5.10.1 built from commit A works, the same 5.10.1 from
commit B doesn't). That's why a version label maps to a spec you
control — pin it to a specific flake input or commit rather than
trusting the version string alone to mean one exact build.

REQUIRED WIRING IN flake.nix

`inputs` and `system` must reach this module via specialArgs, since
the flake-input and raw-commit spec branches need them:

  specialArgs = { inherit inputs; system = "x86_64-linux"; };
  # (or wherever your system string comes from)

FILES

  default.nix              options schema (sources, packages, and the
                            per-package versions/default submodule)
  main.nix                 resolution entrypoint; turns declared
                            packages into environment.systemPackages,
                            also writes /etc/packages-hash-manifest.json,
                            defines the packagesHashDiscovery activation
                            script (see HASH DISCOVERY above), and checks
                            alias names are globally unique (see CUSTOM
                            ALIASES above) via config.assertions -- NOT a
                            top-level `assert` wrapping the module's
                            returned attrset, which forces evaluation
                            before the module system can even inspect
                            the module's shape and causes real infinite
                            recursion; config.assertions is lazy,
                            checked only after config resolves
  lib/default.nix           wires up the helper functions below
  lib/resolve-default.nix   no-versions case (plain, unsuffixed pkg)
  lib/resolve-versions.nix  versions case: suffixed + aliased copies,
                            default (both unsuffixed and "-latest"),
                            returns { drvs; manifestEntries; aliasNames; }
  lib/wrap-aliased.nix      builds the "@<alias>" wrapper derivation
                            (see CUSTOM ALIASES above)
  lib/resolve-spec.nix      turns one spec string into { drv;
                            manifestEntry; } -- manifestEntry is only
                            ever non-null for a bare-"#" spec
  lib/validate.nix          checks that default is a key of versions
  lib/wrap-suffixed.nix     builds the suffixed-bin/ wrapper derivation

NOTE: the flake-input and raw-commit spec branches always resolve
through plain top-level `pkgs.<packageName>` in the imported nixpkgs,
regardless of which `sourceName` (e.g. pkgs.kdePackages) the package
was declared under. They don't know how to walk into non-pkgs
sources — only the ""/"latest" branch respects the declared source.
