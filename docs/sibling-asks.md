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

### W3. A wild hive block of the world's own (2026-09-26): ANSWERED by the world, 2026-10-14 (World 27193d7)

**Wanted.** Hives the flower forest is generated with.

**Answered.** `wild_hive`: a 19-cell lump of comb hung under the first limb
of one apple tree in six in the flower forest, two or three blocks over the
ground. The world registers no tick and no use on it; the honey is this
mod's (husbandry.lua). This mod's stand-in, which hung its own `beehive`
under the trees as players came near, is gone.

**One thing it could not be: filled by random tick.** The comb shares its
block with the bough's wood, and the engine offers no random tick to a
block of more than one material (`material_at` answers nothing for one),
so a wild hive is filled by the clock instead, asked at the right-click:
full when first found, and again `wild_hive_refill_ticks` (forty minutes)
after it was emptied, if flowers are near. It is not drawn full; the honey
is the answer. Flowers are looked for three blocks down now, since the
hives hang that high.

## Tiamat Default Magic and Tiamat Default Science

Their asks of this mod (each repo's `docs/sibling-asks.md`), all answered
2026-09-30 (docs/exports.md has the shapes):

- **L-M1**, a per-player stat ceiling: `set_stat_max(uuid, id, max)`; at 0
  the bar is not drawn for that player.
- **L-M2**, effects and health on others: `add_effect`, `cure`, `heal`,
  `hurt`, for players and this mod's creatures.
- **L-M3 / L-S3**, composed abilities: `set_ability(uuid, source, {
  speed_mul, fly })`, combined with this mod's cold and hunger.
- **L-M4 / L-S5**, the worn view: a promise, in docs/exports.md.
- **L-M5**, steering a creature: `follow(entity, uuid, ticks)`.
- **L-M6**, air: `set_air(uuid, n)` and the `water_breathing` effect.
- **L-M7**, the phoenix: `on_death(fn(uuid, pos, drops))` and
  `keep_inventory(uuid)`.
- **L-S2**, acting on creatures: `push(entity, velocity)` and
  `freeze(entity, ticks)`.
- **L-S4**, moving drops: yes, and `pull_drops(pos, radius, strength)`.
- **L-S7**, gravity (asked 2026-09-30, answered 2026-10-05): `gravity`
  (0..4) in `set_ability`, multiplied across sources and handed to the
  engine with this mod's speed and flight; a fall hurts by its height times
  the gravity it fell under.
- **L-S6**, a tether: a lead right-clicked at a fence post ties everything
  you lead to it, a lead's length from the post, remembered with the
  world; a lead at the animal unties it. One player leading two was
  already so: every animal holds its own lead.

## Tiamat Default Progress

Its asks of this mod (its `docs/sibling-asks.md`), all three answered
2026-09-28: **L6**, the survival events, as `on_kill`, `on_death`, `on_eat`
and `on_sleep`; **L7**, `mode()`, `is_ghost(uuid)` and `is_admin(uuid)`;
**L8**, `add_stat(id, spec)` with `stat`, `set_stat` and `spend_stat`, a
stat this mod keeps, fills back, saves and draws as a bar above the hearts
in the adder's colour. Nothing is asked of it.

## Tiamat Default Craft

Its `docs/sibling-asks.md` asks this mod for `add_food` and `add_weapon`;
both are exported (`docs/exports.md`), with `add_drop`, `add_feed`,
`add_crop`, `add_harvest_tool`, `add_tilling_tool` and `drop` beside them,
so that a tool in bronze or iron, an engineered crop or a cooked meal is
registered through the same code as this mod's own.

### C1. The kitchen (2026-09-26): ANSWERED by Craft, 2026-09-28

Bread (the kiln, from wheat) and hot stew (a fire and a copper pot) are
Craft's to make, and it hands out THIS mod's items, so their buffs are
written in this mod's own definitions: `steady` on bread and `hearty` on
hot stew (items.lua), since an `add_food` from Craft would replace this
mod's numbers wholesale (Craft's L9, answered 2026-09-28). Cured meat waits
on Craft's salt recipe.

### C2. Leather, cord and cloth (2026-09-26): ANSWERED by Craft, 2026-09-28 and 2026-10-14

Hide, sinew, bone, wool and feathers drop from the animals (each kind's
`drops`, and `add_drop` for more), and Craft makes them into things: leather
(a hide tanned with bark), cord from sinew, cloth from wool and a bone
needle (2026-09-28), with this mod's warm coat, cool cloak and bandages
sewn from them, and bellows of leather. Feathers are bedding since Craft
452d034 (2026-10-14): three of them, as hide, wool and grass are, for this
mod's bed at the workbench. Not built, and not owed: bowstrings wait on a
bow, which no mod has, and a bed that is not a block is this mod's to make
if it wants one.
