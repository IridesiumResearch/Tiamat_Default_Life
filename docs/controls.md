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

The engine has operators (its `server.toml` list; in a world you host, you)
and gives them one power, flight. It cannot yet tell a mod who they are, so
this mod keeps its own list, begun the same way: **whoever first joins a
world is its admin.** Admins make more.

| Word | Who | Does |
|---|---|---|
| `mode` | anyone | Says what kind of world this is, and whether you are an admin. |
| `vitals` | anyone | Your numbers, on the HUD and in the log. |
| `kit` | creative worlds, or admins | One of everything. |
| `god` | admin | Indestructible, on and off. Nothing hurts, nothing drains, hunters ignore you. |
| `tp <x> <y> <z>` / `tp <name>` / `tp home` | admin | Goes there. |
| `revive [name]` | admin | Raises a ghost, yourself included. |
| `op <name>` / `deop <name>` / `admins` | admin | The list. A world keeps at least one. |
| `hurt`, `heal`, `feed`, `starve`, `poison`, `wither`, `burn`, `choke`, `freeze`, `roast`, `boom`, `die`, `spawn`, `mobs`, `cull` | admin | The testing words. `dev_commands = false` in `config.lua` removes them altogether. |

Flight stays the engine's: its operators fly, in any mode, and nobody else.

## This mod's keys

| Key | Action | Notes |
|---|---|---|
| **X** | Use what you hold: eat, bandage, antidote. Empty-handed beside a bed: sleep. | |
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

| Key now | Action | A cheat? | Agreed |
|---|---|---|---|
| **N** | Fly | It is a power, and it is already gated: operators only, server-enforced. | Keep. |
| **[ ] \\** and PageDown, PageUp, Home | Wind your own sky back, on, and resync | **Yes.** Client-side only, but it turns your night into day on your own screen: seeing in the dark for free in a survival or one-life world. | A **server permission**, decided where flight is. Taking the default keys away is not enough, since anybody can bind them again. |
| **F8, Y** / **F7, H** | "Teleport" far and home | No. It shifts the render origin for the floating-point test; your body does not move. | Off the letters: F7 and F8 only. No permission. |
| **G** | Lay out one of every block | No. Singleplayer only already (it writes through the embedded server). | Off the letter: F9. No permission. |
| **B** | Chunk borders | No. It draws lines. | Off the letter: F4. No permission. |

Letters this frees for games: **B, G, H, Y**, and with the laptop twins of
lighting and third person reconsidered, **L** and **V** as well.

### What a mod needs from the engine to finish the job

Filed in `engine-asks.md`:

- `game.is_operator(uuid)`, so this mod's admins ARE the engine's operators
  and the two lists cannot disagree.
- `game.set_player_abilities(uuid, { fly = true, speed = ..., sprint = ... })`,
  so a creative world can let everybody fly without making everybody an
  operator, and cold and hunger can slow a player. It has to travel to the
  client, which predicts its own movement: an ability the client does not
  know about is rubber-banding for as long as it lasts.
- A server permission on the sky keys, and the debug keys moved off the
  letters, as in the table above.
