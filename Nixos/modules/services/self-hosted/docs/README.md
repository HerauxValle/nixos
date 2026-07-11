# self-hosted docs

- [`architecture.md`](./architecture.md) -- how everything works: the
  shared `self-hosted.nix` primitives, the action naming conventions
  (`:target`, `:apply`), the store/installed pattern, secrets,
  `~/.impure/`.
- [`adding-a-service.md`](./adding-a-service.md) -- step-by-step guide
  to porting a new service into this framework.
- [`conventions.md`](./conventions.md) -- the rules that keep this
  system generalized without over-generalizing, and the concrete
  mistakes each rule exists because of.

For a specific service's own options/actions/workflows, read that
service's `<name>/info.md` instead -- these three files only cover what's
shared across all of them.
