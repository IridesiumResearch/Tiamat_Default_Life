<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Exports

What Tiamat Default Life (`tiamat_default_life`) deliberately offers other
mods. This is the document `LICENSE.EXCEPTION` names as "the Exports": a mod
that reaches this one only through what is listed here, the engine's
scripting API or the network protocol is an independent work. A mod that
copies or adapts this mod's code or assets is not, and stays under the GPL.

An interface this mod offers in fact is an export whether or not it is listed
here, so this file changes in the same commit as any change to one.

## The exported table

`game.exports("tiamat_default_life")` answers it to a mod that lists this one
in `depends` or `optional_depends`. Source: `mods/tiamat_default_life/exports.lua`.

| Field | Shape | What it does |
|---|---|---|
| `version` | integer, `1` | Bumped only when a change would break a reader. |
| `add_contact_fire(material, spec)` | `material` a `"mod:block"` name; `spec = { damage, ticks, after }` — whole numbers, `damage` 1..27, `ticks` 1..1200, `after` 0..1200 | Standing in `material` burns: `damage` points every `ticks` ticks, then `after` ticks of burning once out of it. Answers whether it was taken. |
| `set_alight(target, ticks)` | `target` a player's UUID (hex string) or the integer entity id of one of this mod's creatures; `ticks` 1..1200 | Sets `target` burning until it runs out or they reach water. Answers whether there was anyone to set alight. |
| `add_heat_source(material, strength)` | `material` a `"mod:block"` name; `strength` a number 0..1 | Warms whoever stands near `material`, as the campfire does at 1. Answers whether it was taken. |
| `add_food(material, spec)` | `material` your item's `"mod:item"` name, registered; `spec = { food, saturation, heal, effects = { { id, ticks } }, cures = { id }, well_fed, temperature = "warm"\|"cool", sound = "eat"\|"drink" }`, every field optional, effects and cures this mod's (`effects.lua`, which includes `hearty` and `steady`) | Eating it, with X or the right mouse, does what the spec says. Answers whether it was taken. |
| `add_weapon(material, damage)` | `material` your item's name; `damage` a whole number 1..100 | A punch with it in hand does `damage` points to a creature or a player (a fist does one). |
| `add_drop(kind, material, min, max)` | `kind` one of this mod's creatures, by short id (`"cow"`); `material` your item's name; whole numbers 0..64 | The creature also leaves `min` to `max` of your item when it dies. |
| `add_feed(material, kinds)` | `material` your item's name; `kinds` a list of short ids | Your item is feed for those kinds: a fed animal is ready to breed. |
| `add_crop(def)` | `def = { id, stages = { "mod:block", ... } (2..8 of YOUR blocks, sprouting first, ripe last), seed = "mod:item", produce = "mod:item", produce_min, produce_max, seed_min, seed_max, soil = "tilled"\|"wet"\|{ "mod:block", ... }, light = "sun"\|"dark", biomes = { ids }, name }` | Your crop is sown, grown by random tick and harvested by this mod's rules, exactly as its own are. Register the stage blocks yourself (a texture is a file of the registering mod) and do NOT random-tick them: this mod does, and the engine allows one handler per material. Registration window only. |
| `add_harvest_tool(material, yield)` | `material` your item's name; `yield` a number 1..8 | A ripe crop dug with it gives `yield` times a hand's produce (this mod's sickle gives two). |
| `add_tilling_tool(material)` | `material` your item's name | Grass or earth right-clicked with it is tilled ground. |
| `drop(pos, stack, opts)` | `pos = { x, y, z }`; `stack = { material, units \| count, shape, detail }`; `opts = { velocity = { x, y, z }, owner = uuid }` | Puts a stack on the ground in this mod's care: picked up by whoever walks over it, gone after five minutes. Answers the entity id, or `nil`. |

None of them raise: anything malformed answers `false` (or `nil`, for
`drop`). Tiamat Weather is one reader (its `docs/exports-contract.md`);
Tiamat Default Craft, which will cook, mill and forge, is the other
(`add_food`, `add_weapon`, and the farm tools in bronze and iron), and
until it exists this mod's own hoe, sickle, shears and bucket stand in.

## Identifiers it registers

All are namespaced `tiamat_default_life:` by the engine.

- **Blocks:** `bed`, `campfire`, `farmland`, `wet_farmland`, `fence`, `gate`,
  `gate_open`, `beehive`, `beehive_full`, `bramble_picked`, and the crop
  stages `wheat_1`..`wheat_3`, `turnip_1`..`turnip_3`, `rice_1`..`rice_3`,
  `melon_1`..`melon_3`, `mushroom_1`..`mushroom_2`.
- **Items:** `apple`, `berries`, `bread`, `raw_meat`, `cooked_meat`,
  `hot_stew`, `cool_melon`, `honey`, `golden_apple`, `bandage`, `antidote`,
  `warm_coat`, `cool_cloak`; the farm's `turnip`, `rice`, `mushroom`, `egg`,
  `milk`, `wheat`, `wheat_seeds`, `turnip_seeds`, `rice_seeds`,
  `melon_seeds`, `spores`, `bramble_cane`, `hoe`, `sickle`, `shears`,
  `bucket`, `water_bucket`, `lead`, `wool`, `feather`, `hide`, `bone`,
  `sinew`.
- **Creatures** (entity models, and the kind read back off an entity):
  `cow`, `sheep`, `pig`, `hen`, `horse`, `goat`, `bunny`, `fox`, `squirrel`, `wolf`,
  `mammoth`, `spider`, `scurrier`, `cave_rat`, `cave_troll`, `swamp_hag`, `scarecrow`, `ghost`, `bear`,
  `stag`, `crow`, `bat`; and, for the kinds that breed, a young body
  `<kind>_young` (the same model at half size), which is how a young one is
  told from a grown one across a restart.
- **Sounds** (each also bound as a cue of the same name, so a sound pack can
  rebind it): `hurt`, `eat`, `drink`, `heal`, `bubble`, `gasp`, `burn`,
  `death`, `thud`, `rested`, `boom`, `bite`, `moo`, `baa`, `oink`, `oink_2`,
  `snort`, `bleat`, `bell`, `growl`, `growl_2`, `growl_3`, `caw`, `caw_2`,
  `squeak`, `flap`, `yip`, `bark`, `trumpet`, `hiss`, `hiss_2`, `underwater`.
- **Pictures:** `icon_heart_full`, `icon_heart_2`, `icon_heart_1`,
  `icon_heart_empty`, `icon_heart_flash`, `icon_cookie_full`,
  `icon_cookie_half`, `icon_cookie_empty`, `icon_bubble`, `icon_thermo_hot`,
  `icon_thermo_cold`, `icon_shield`, `icon_shield_faint`, `icon_shield_broken`.
- **Actions:** `use`, `wardrobe`.
- **Inventory view:** `worn` (four slots).
- **World option:** `mode` — `"Default"`, `"Creative"` or `"Adventure"`,
  readable by any mod as `game.world_option("tiamat_default_life:mode")`.

## Commands it accepts

Chat words, said by a player and swallowed. `anyone`: `vitals`, `mode`.
`creative` (everyone in a Creative world, admins anywhere): `kit`. Admin:
`hurt`, `heal`, `feed`, `starve`, `poison`, `wither`, `burn`, `choke`,
`freeze`, `roast`, `boom`, `die`, `spawn` (`spawn <kind> [n] [young]`),
`mobs`, `mob`, `plan`, `odds`, `ignite`, `cull`, `god`, `tp`, `revive`, `admins`.

## Data it stores or sends

None for other mods. `game.storage` is private to this mod, and the values
pushed with `game.set_hud` are read only by this mod's own HUD script.

## What it reads from other mods

Not exports, listed so the direction is clear: it reads the exports of
`tiamat_default_world` (`biome_under`, for where creatures appear and crops
belong; `add_soil_alias`, which it calls so tilled ground counts as dirt)
and `tiamat_default_ui` (for the wardrobe tab and the death screen) when
they are loaded, and looks up the world's blocks by name in `config.lua`.
It never reads Tiamat Weather, which loads after it: rain reaches the farm
through the engine, as a fluid tilled ground absorbs.
