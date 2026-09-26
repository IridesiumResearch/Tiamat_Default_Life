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

None of them raise: anything malformed answers `false`. Tiamat Weather is the
current reader (its `docs/exports-contract.md`).

## Identifiers it registers

All are namespaced `tiamat_default_life:` by the engine.

- **Blocks:** `bed`, `campfire`.
- **Items:** `apple`, `berries`, `bread`, `raw_meat`, `cooked_meat`,
  `hot_stew`, `cool_melon`, `honey`, `golden_apple`, `bandage`, `antidote`,
  `warm_coat`, `cool_cloak`.
- **Creatures** (entity models, and the kind read back off an entity):
  `cow`, `sheep`, `pig`, `horse`, `goat`, `bunny`, `fox`, `squirrel`, `wolf`,
  `mammoth`, `spider`, `scurrier`, `cave_troll`, `swamp_hag`, `scarecrow`, `ghost`, `bear`,
  `stag`, `crow`, `bat`.
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
`freeze`, `roast`, `boom`, `die`, `spawn`, `mobs`, `mob`, `plan`, `odds`,
`ignite`, `cull`, `god`, `tp`, `revive`, `admins`.

## Data it stores or sends

None for other mods. `game.storage` is private to this mod, and the values
pushed with `game.set_hud` are read only by this mod's own HUD script.

## What it reads from other mods

Not exports, listed so the direction is clear: it reads the exports of
`tiamat_default_world` (for its blocks) and `tiamat_default_ui` (for the
wardrobe tab and the death screen) when they are loaded, and looks up the
world's blocks by name in `config.lua`.
