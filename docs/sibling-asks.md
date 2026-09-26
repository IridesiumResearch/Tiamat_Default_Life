<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Asks of the sibling mods

What this mod needs from the OTHER mods beside the engine — the world, the
weather, the craft mod that is coming — as `docs/engine-asks.md` holds what
it needs from the engine. Each says what was wanted, what stands in for it
today, and the smallest change that would answer it. Newest first.

## Tiamat Default World

### W1. A wild grain, so the first wheat is found rather than foraged (2026-09-26): OPEN

**Wanted.** A block of wild wheat (or barley) standing in the grassland and
river meadows the way tall grass does, so a player finds the crop before
they find a seed.

**Standing in.** Tall grass dug gives wheat seeds one time in five
(`config.lua`, `forage`), and heather or lichen turnip seeds, reeds rice,
the jungle's monstera and pitcher plant melon seeds, glow caps spores. It
works, and it is invisible: nothing in the world looks like grain.

**Smallest change.** A `wild_wheat` block (billboard, passable, sway, like
tall grass) scattered thinly through `rolling_grasslands` and
`river_valleys`; this mod would forage wheat seeds from it every time and
leave tall grass alone.

### W2. Apples on apple trees (2026-09-26): OPEN

**Wanted.** Fruit that is SEEN: an apple hanging in an apple tree, picked
with a right-click, back a while later.

**Standing in.** An apple leaf block broken has an apple in it one time in
seven, a blossom one in twenty. The tree is dug to be eaten from, which is
wrong for a tree.

**Smallest change.** Either an `apple_fruit` block the world's apple tree
random-ticks into place under its leaves now and then (this mod would pick
it and put the leaf back), or a random tick on `apple_leaves` this mod may
ask for through an export, since the engine allows one handler per material
and the leaves are the world's.

### W3. A wild hive block of the world's own (2026-09-26): OPEN, low

**Wanted.** Hives the flower forest is generated with.

**Standing in.** This mod hangs its own `beehive` under the forest's trees
as players come near, one to a chunk at most, remembered with the world.
It is a spawn pass, not worldgen, so a hive is never in a chunk nobody has
walked to — which nobody can tell.

## Tiamat Default Craft (not yet built)

Its `docs/sibling-asks.md` asks this mod for `add_food` and `add_weapon`;
both are exported (`docs/exports.md`), with `add_drop`, `add_feed`,
`add_crop`, `add_harvest_tool`, `add_tilling_tool` and `drop` beside them,
so that a tool in bronze or iron, an engineered crop or a cooked meal is
registered through the same code as this mod's own.

### C1. The kitchen (2026-09-26): OPEN, and Craft's to build

Bread, hot stew and cured meat have no source in this mod, by decision:
heat stations, milling and the recipe registry are Craft's. This mod's
side is ready — wheat, salt (the world's), raw meat and produce exist, and
`hearty` and `steady` are effects a cooked meal may carry through
`add_food`. When Craft registers bread with `effects = { { "steady", ... } }`
and a stew with `hearty`, the buffs are live.

### C2. Leather, cord and cloth (2026-09-26): OPEN, and Craft's to build

Hide, sinew, bone, wool and feathers drop from the animals now (each kind's
`drops`, and `add_drop` for more). What they become — leather armour,
bowstrings, needles, bellows, a bed that is not a block — is Craft's.
