<!-- &desc: "Complete CLI tree for cas, ASCII-tree style -- every action, sub-action, and flag in the tool, one sentence each. Complements docs/cli.md (table-format reference) and 'cas help <action>' (interactive, with examples) rather than replacing either." -->
# CLI layout

Every command `cas` has, laid out as a tree. Flags may appear anywhere
in the command line, not just where shown. `<vault>` is the vault name
(or a bare path/`.img` file to toggle it open/closed). One sentence per
node — see `docs/cli.md` for the table-format reference and `cas help
<action>` for interactive help with examples.

```
cas
│
├── list [--path dir]                      list every vault found nearby
├── quit                                    alias for `all close`
├── all close                               close every open vault on this machine
├── --version | -V | version                print the cas version
├── help [<action>]                         show global help, or one action's detailed help
├── debug <subcommand>                      dev/introspection tools, no vault needed
│   └── parse-cli                           dump the compiled-in KDL registry as ASCII, with
│                                            an Ignored/Duplicate consistency check
├── <path/to/vault.img>                     bare path toggle: open if closed, close if open
│
└── <vault> <action> ...
    │
    ├── create [--size MiB] [--strength lvl] [--pass "..."] [--test]
    │                                        make a new vault, prompts for size/passphrase if not given
    │
    ├── open [--pass "..."] [--keyfile path]
    │                                        unlock and mount the vault, running any pending schema migration
    │
    ├── close [--force]                     lock the vault again, --force skips the busy-mount check
    │
    ├── toggle [--pass "..."] [--keyfile path]
    │                                        open if closed, close if open
    │
    ├── rename <newname>                    rename the vault file (must be closed)
    │
    ├── resize <size>  (alias: shrink)      grow or shrink the vault (accepts M/MiB/G/GiB/T/TiB)
    │
    ├── delete [--removeKeyfile] [--shred]  permanently delete the vault file, asks to confirm
    │
    ├── info [--pass "..."]                 show vault details plus every setting's enabled/disabled state
    │
    ├── tampered [--pass "..."]             check the tamper-evidence HMAC against the last verified write
    │
    ├── auth
    │   ├── passwd [--pass "..."] [--new-pass "..."] [--strength lvl]
    │   │                                    change the vault's passphrase
    │   └── keyfile
    │       ├── move <location> [--keyfile path]
    │       │                                move the active keyfile to a new location
    │       ├── reset [location] [--keyfile path]
    │       │                                generate a brand-new keyfile and re-key the vault, irreversible
    │       ├── embed <carrier-file> [--keyfile path]
    │       │                                hide the keyfile's bytes appended inside another file
    │       ├── extract <carrier-file> [location]
    │       │                                pull a previously-embedded keyfile back out of a carrier
    │       ├── strip <carrier-file>         remove embedded keyfile bytes from a carrier, leaving the original file intact
    │       └── activate <location>          make a keyfile at an arbitrary location the vault's active one
    │
    ├── backup
    │   ├── create <name>                    take a manual named btrfs snapshot
    │   ├── list                             show manual and auto snapshots separately
    │   ├── restore <name>                   restore the vault's contents from a snapshot
    │   ├── delete <name>                    delete a manual snapshot
    │   └── rootfs
    │       ├── include <name>               opt a rootfs environment into future snapshots (excluded by default)
    │       ├── exclude <name>                opt it back out
    │       └── state                        list which rootfs environments are currently included
    │
    ├── settings
    │   ├── encryption enable|disable|state  toggle passphrase-prompt UX vs. an autokey stored in metadata
    │   ├── 2fa enable|disable|state         add/remove a second-factor keyfile requirement
    │   │
    │   ├── backup
    │   │   └── auto enable [--keep N]|disable|keep <N>|state
    │   │                                    automatic snapshot-on-open, with a rolling keep count
    │   │
    │   ├── verification
    │   │   ├── state                        show which features currently require re-verification
    │   │   └── <feature> enable|disable|state
    │   │                                    require re-proving the real passphrase before <feature> can change
    │   │
    │   └── security
    │       ├── ransomwareProtection enable|disable|state
    │       │                                lock .casket/ to root-only, unreadable/unwritable by the vault's own user
    │       ├── zeroize enable|disable|state locks the derived secret in RAM and scrubs it from memory when done
    │       ├── bruteforceLockout enable [--threshold N]|disable|threshold <N>|state
    │       │                                delete the vault after N consecutive wrong passphrases
    │       └── sandbox
    │           ├── enable                   permit `cas <vault> exec` for this vault
    │           ├── disable [--removeRootfs] block `exec`, optionally wiping every rootfs environment too
    │           ├── state                    show whether sandbox is enabled
    │           │
    │           ├── namespaces
    │           │   ├── set <list>           replace the active namespace set outright (mount/pid/uts/ipc/user/net)
    │           │   ├── enable <list>        add namespaces to the active set
    │           │   ├── disable <list>       remove namespaces from the active set (`user` can't be removed)
    │           │   └── state                show which namespaces are currently active
    │           │
    │           ├── network                  (generated from cli/registry.kdl -- run
    │           │                             `cas debug parse-cli` for the live compiled tree)
    │           │   ├── outbound enable|disable|state
    │           │   │                        real veth+NAT outbound connectivity for `exec`, requires `namespaces net`
    │           │   └── inbound
    │           │       ├── add <hostPort>[:<sandboxPort>] [--protocol tcp|udp]
    │           │       │                    configure a host port to forward into the sandbox
    │           │       ├── remove <hostPort>
    │           │       │                    stop forwarding a host port
    │           │       ├── list             show every configured port forward
    │           │       ├── enable           turn on forwarding for the configured ports
    │           │       ├── disable          turn off forwarding (port list is kept)
    │           │       └── state            show whether inbound forwarding is enabled
    │           │
    │           ├── rootfs
    │           │   ├── list                 show every named rootfs environment, and which is `default`
    │           │   ├── add <name> --preset <distro> [<version>] | --tarball <path>
    │           │   │                        create a named environment from a live distro fetch or a local tarball
    │           │   ├── update <name> [<version>] | --tarball <path>
    │           │   │                        replace only base/, leaving anything installed in upper/ untouched
    │           │   ├── remove <name>|<name,name,...>|all
    │           │   │                        permanently delete one, several, or every environment (typed confirm each)
    │           │   ├── rename <old> <new>   rename an environment, carrying the `default` pointer forward if it applied
    │           │   └── default <name>|--clear
    │           │                            set or clear which environment `exec` uses when several exist and none is named
    │           │
    │           ├── seccomp
    │           │   ├── [--rootfs <name>] set <name>
    │           │   │                        choose which filter a target uses -- built-in presets
    │           │   │                        (default/strict/compute/none) and custom profiles share one
    │           │   │                        flat namespace, no prefix needed to tell them apart.
    │           │   │                        `--rootfs _root` explicitly means the vault's own content --
    │           │   │                        the only way to reach it once any real environment exists
    │           │   │                        (otherwise a lone environment is auto-selected instead).
    │           │   │                        Same sentinel works for `exec --rootfs _root` too.
    │           │   ├── [--rootfs <name>] state
    │           │   │                        show the active filter for a target
    │           │   │
    │           │   └── custom                manage named custom seccomp profiles (vault-wide, reusable
    │           │       │                      across every rootfs environment and the vault's own root target;
    │           │       │                      `create`/`rename` refuse any name colliding with a built-in preset)
    │           │       ├── list               every profile that exists, and which targets use each
    │           │       ├── create <name>      create a new empty profile (default action: deny)
    │           │       ├── delete <name>      delete a profile -- refuses if any target still references it
    │           │       ├── rename <old> <new> rename a profile; every target referencing it follows the rename
    │           │       └── edit <name>
    │           │           ├── (no args)      opens $EDITOR on the profile's raw TOML
    │           │           ├── default <allow|deny>
    │           │           │                  set the profile's fallback action for syscalls in neither list
    │           │           ├── add [--allow <list>] [--deny <list>]
    │           │           │                  add syscalls (names or numeric ids, auto-resolved) to one or
    │           │           │                  both lists; a bare list with no flag means --allow
    │           │           ├── remove [--allow <list>] [--deny <list>]
    │           │           │                  same scoping as `add`, removes instead
    │           │           └── status         show the profile's default action + full allow/deny lists
    │           │
    │           └── cgroups
    │               ├── set [--mem <val>] [--cpu <percent>] [--pids <n>]
    │               │                        cap memory/CPU/process-count for exec sessions
    │               ├── clear                remove all cgroup limits (back to unlimited)
    │               └── state                show the currently configured limits
    │
    └── exec [--rootfs <name>] [-- <cmd> ...]
                                             drop a shell (or run one command) namespace-isolated inside the vault
```

## Global flags (valid anywhere in the command line)

`--pass "..."`, `--new-pass "..."`, `--keyfile <path>`, `--size <MiB>`,
`--strength <light|medium|hard|extreme>`, `--path <dir>`,
`--removeKeyfile`, `--shred`, `--test`,
`--no-log`, `--no-confirm`, `--debug`.

## Note on the `network` subtree above

`settings security sandbox network` is generated from `cli/registry.kdl`,
the CLI's KDL-driven single source of truth for shape (names, nesting,
ids, help text) -- see `changelog/1.17.0.md` for why. `cas debug
parse-cli` prints the live compiled tree directly from the binary,
which is the authoritative version if this file and the binary ever
disagree. Everything else in this document is still the original
hand-maintained tree; migrating more of the CLI onto the KDL system is
future work.
