<!-- &desc: "Pumpkin+PatchBukkit research (2026-08-09) -- why hardcore/ launched on Paper instead, and what a later switch actually involves." -->

# Pumpkin/PatchBukkit -- research notes (2026-08-09)

`hardcore/` runs Paper, not Pumpkin. This documents why, and what it'd
take to switch once Pumpkin matures -- so that decision doesn't need
re-researching from scratch later.

## What Pumpkin/PatchBukkit are

- **[Pumpkin](https://github.com/Pumpkin-MC/Pumpkin)** -- a from-scratch
  Minecraft Java Edition server implementation written in Rust. Not a
  Paper/Spigot fork; a clean-room reimplementation of the protocol and
  game logic.
- **[PatchBukkit](https://github.com/Pumpkin-MC/PatchBukkit)** -- a
  compatibility layer that embeds a JVM inside a Rust Pumpkin plugin,
  letting you drop Bukkit/Spigot/Paper plugin jars into a
  `patchbukkit-plugins/` folder.

## Why not now

1. **Core gameplay systems are unfinished, not just rough.** Pumpkin's
   own README (as of 2026-08-09) lists chunk generation, redstone, mob
   AI, combat systems, and boss entities as incomplete/in-progress.
   Chunk generation and combat being unfinished rules out actually
   playing a hardcore survival world on it right now -- not a
   plugin-ecosystem concern, a "the game itself doesn't fully work yet"
   concern.

2. **PatchBukkit only reimplements the public Bukkit API surface**, not
   CraftBukkit's internal NMS classes (confirmed via its own
   `ARCHITECTURE.md`). Plugins that reach past the public API into NMS
   reflection -- ProtocolLib being the flagship example, and a
   dependency of a large share of the popular QoL plugin ecosystem
   (custom tab lists, scoreboards, packet-level chat tools) -- are
   explicitly called out as incompatible and will fail outright.

3. **Toolchain coupling is fragile.** PatchBukkit's docs state the
   Pumpkin server and PatchBukkit itself must be built against the same
   Rust *nightly* toolchain -- not even stable -- so every Pumpkin
   update risks breaking the pairing until PatchBukkit catches up.

4. **No `nix-minecraft` packaging exists.** Checked the flake's outputs
   directly (`nix flake show github:Infinidoge/nix-minecraft`) --
   vanilla/paper/purpur/quilt/fabric/neoforge/velocity are all there,
   Pumpkin is not. Running it today would mean packaging a
   nightly-Rust-pinned, still-heavy-development server from source,
   outside the declarative pipeline every other server here uses.

## Switching later IS clean, once it's mature

World data (region files, `level.dat`, `playerdata/`) is stored in the
standard vanilla Anvil/NBT format regardless of server software --
that's the actual save-file spec, not a Paper-specific thing, and
Pumpkin has to read/write it correctly to stay compatible with vanilla
clients at all. So the migration path, whenever it's actually viable:

1. Stop `hardcore.service`, back up the world folder (as always before
   any server-software swap).
2. Point a Pumpkin+PatchBukkit setup at that same world folder --
   no conversion step needed.
3. Nix side: swap `hardcore/package.nix`'s `package` once Pumpkin has a
   real `nix-minecraft` output (or a hand-packaged derivation you trust),
   and re-add any plugins as PatchBukkit-compatible jars in a new
   `plugins.nix` (mirroring `creative/plugins.nix`'s pattern).

## Re-check before switching

- Has chunk generation/combat/mob AI actually shipped (not just "in
  progress")? Check Pumpkin's own issue tracker / 1.0.0 milestone.
- Does PatchBukkit's NMS/reflection story still exclude ProtocolLib and
  similar plugins, or has that changed?
- Is the nightly-toolchain coupling still required, or has it stabilized?
- Has `nix-minecraft` picked up a Pumpkin package yet?
