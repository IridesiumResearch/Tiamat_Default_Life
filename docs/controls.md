# Controls, powers and modes

Who may do what, on which key, in which kind of world. Two layers:

- **The engine owns every key.** A mod names an action and suggests a
  default; it cannot read a key, move an engine binding, or put an engine
  control behind a permission. So the engine's own bindings are sorted here
  as a PROPOSAL (and filed in `engine-asks.md`), and this mod's are sorted
  for real.
- **This mod owns the rules.** Modes, admins, being indestructible, going
  anywhere and raising the dead are all here, in `modes.lua`.

## The three modes

Chosen on the new-world screen (a world option, `tiamot_default_life:mode`)
and fixed for the life of the world, as the seed is. A dedicated server sets
it under `[world_options]` in `server.toml`.

| Mode | What it is |
|---|---|
| **Default** | Survival: hearts, hunger, air, warmth. Die and a third of what you carry falls; you wake at your bed or where you last stood safely. |
| **Creative** | Nobody can be hurt and nothing drains. No hearts or cookies on the HUD. Hunters ignore you. Anyone may say `kit`. |
| **Adventure** | One life. Die and EVERYTHING falls, worn and carried, and you stay as a ghost: you may walk the world and watch it, and you dig, place, use, punch, eat and pick up nothing, for good, across rejoins. Only an admin's `revive` undoes it. |

## Admins

**Admins are the engine's operators** (its `server.toml` list; in a world
you host, you), read with `game.is_operator`. The engine's own `/op` and
`/deop` make and unmake them, and this mod keeps no list of its own.

| Word | Who | Does |
|---|---|---|
| `mode` | anyone | Says what kind of world this is, and whether you are an admin. |
| `vitals` | anyone | Your numbers, on the HUD and in the log. |
| `kit` | creative worlds, or admins | One of everything. |
| `god` | admin | Indestructible, on and off. Nothing hurts, nothing drains, hunters ignore you. |
| `tp <x> <y> <z>` / `tp <name>` / `tp home` | admin | Goes there. |
| `revive [name]` | admin | Raises a ghost, yourself included. |
| `admins` | admin | Who here is one. Making more is the engine's `/op`. |
| `hurt`, `heal`, `feed`, `starve`, `poison`, `wither`, `burn`, `choke`, `freeze`, `roast`, `boom`, `die`, `spawn`, `mobs`, `cull` | admin | The testing words. `dev_commands = false` in `config.lua` removes them altogether. |

Operators fly, in any mode. In a creative world this mod lets everybody
fly (`game.set_player_abilities`), which is not making anybody an operator.

## This mod's keys

| Key | Action | Notes |
|---|---|---|
| **X** | Use what you hold: eat, bandage, antidote. Empty-handed, at the bed you look at or one beside you: sleep. | |
| **Right mouse** on a bed | Sleep in it. | The engine's place control, with nothing placeable in hand. |
| **O** | Wardrobe: the worn slots. | Was G, which is the engine's debug block row. O for outfit. |

## The engine's keys, as they are and as they should be

Surveyed from `crates/client/src/input.rs` at engine `a9d6349` (2026-09-17).

### Playing: keep as they are

| Key | Action |
|---|---|
| W A S D | Move |
| Space | Jump |
| Left Shift | Sneak |
| Left Ctrl | Sprint |
| Left / right mouse | Break / place, and use with nothing to place |
| 1 to 9 | Hotbar |
| R | Cycle tool |
| F | Swap with the off-hand |
| T | Chat |
| Esc | Release the cursor |
| F1 | Controls and settings |

### Looking: keep, harmless to anybody

| Key | Action | Note |
|---|---|---|
| F3 | Debug overlay | Shows your position. Fine in every mode; a server that minds can ask for it gated later. |
| F5, L | Lighting mode | Two keys for one thing; L is the laptop twin. |
| K | Shadow resolution | |
| F6, V | Third person | |

### Powers and debug keys

Agreed with the engine side, 2026-09-18: a permission belongs only on what
is actually a power. A control that cannot move your body or change the
world needs no gate, only a better key.

Both halves landed in engine 990bf8a (ask 10).

| Key | Action | A cheat? | Now |
|---|---|---|---|
| **N** | Fly | A power. | Operators, and everybody in a creative world (`game.set_player_abilities`). |
| **[ ] \\** and PageDown, PageUp, Home | Wind your own sky back, on, and resync | **Yes.** Client-side only, but it turns your night into day on your own screen: seeing in the dark for free. | A server permission, `wind_sky`. This mod grants it to admins and in creative worlds, and refuses it to everybody else. Resync is never refused. |
| **F8** / **F7** | "Teleport" far and home | No. It shifts the render origin for the floating-point test; your body does not move. | Function keys only; the Y and H twins are unbound. |
| **F9** | Lay out one of every block | No. Singleplayer only. | Moved off G. |
| **F4** | Chunk borders | No. It draws lines. | Moved off B. |

Letters this frees for games: **B, G, H, Y**, and with the laptop twins of
lighting and third person reconsidered, **L** and **V** as well.
