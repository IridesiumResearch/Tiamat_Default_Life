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

### Powers: behind the operator list, and off the letter keys

| Key now | Action | Gated now? | Proposal |
|---|---|---|---|
| **N** | Fly | **Yes**, operators only, server-enforced. | Keep the gate. Hide the row from a non-operator's settings screen, so a key that does nothing is not offered. |
| **[ ] \\** and PageDown, PageUp, Home | Wind your own sky back, on, and resync | **No.** Client-side only, but it turns your night into day on your own screen, which in a survival or adventure world is seeing in the dark for free. | Operators only, enforced where flight is: the client asks, the server says whether this player may. |
| **F8, Y** / **F7, H** | "Teleport" far and home | No, and it is not a teleport: it shifts the render origin for the floating-point test. Your body does not move. | Debug builds or operators only; drop the letter twins Y and H, which are prime keys for a game to want. |
| **G** | Lay out one of every block | Singleplayer only (it writes through the embedded server). | Operators only, and off G: F9. |
| **B** | Chunk borders | No. Harmless, but a letter key. | F4, leaving B free. |

Letters this frees for games: **B, G, H, Y**, and with the laptop twins of
lighting and third person reconsidered, **L** and **V** as well.

### What a mod needs from the engine to finish the job

Filed in `engine-asks.md`:

- `game.is_operator(uuid)`, so this mod's admins ARE the engine's operators
  and the two lists cannot disagree.
- `game.set_player_abilities(uuid, { fly = true })`, so a creative world
  can let everybody fly without making everybody an operator.
- The gates above on the sky-winding and debug keys.
