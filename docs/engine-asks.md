# Engine asks from the Life mod

What the survival layer has needed from the engine, found by building it.
Each entry says what was wanted, why the mod cannot do it, and the smallest
engine change that would. Newest first. Items are removed when they land.

## 0. Models a mod ships (2026-09-11)

**Wanted.** Animals and mobs that look like animals and mobs. A cow, a
wolf, a bird: each a skinned, textured model with its own idle, walk and
run clips.

**Why the mod cannot do it.** `game.spawn_entity{ model = ... }` accepts
any string, but the client draws only `engine:humanoid`; every other name
draws nothing (`crates/client/src/app.rs`, "the engine's rig, or
nothing"). The glTF reader exists in `core::model::ingest` (pure Rust,
embedded-only `.glb`, caps checked before allocation, four weights) and the
content pipeline already lists `.glb` as distributable, but there is no
registration that names one and no client path that loads a pushed one.
Materials and images are skipped entirely, so even the humanoid is matte
white; a model has UVs and nothing to put on them.

**Ask.** In three steps, each useful on its own:

1. `game.register_model{ id = "cow", file = "models/cow.glb" }` at
   registration, pushed by hash like a texture, with the client loading it
   through the existing reader and drawing `tiamot_default_life:cow` where
   it now draws nothing. Clips matched to `AnimTag` by name: `idle`,
   `walk`, `run`, `swing`, `swim`, `sneak`; a missing clip falls back to
   `idle`; no clips at all is a rigid model, still drawn.
2. `texture = "textures/cow.png"` on the same call: one image, sampled by
   the mesh's own UVs, pushed separately as block textures are (which is
   why the reader refuses embedded images). Untextured stays matte white.
3. `scale = 3.0`: the reader takes model space in cells, and a model built
   at one unit to the yard needs a factor rather than a re-export.

Until 1 lands, every mob is a white humanoid or invisible, and the mob
work goes ahead on behaviour, spawning and drops with the humanoid as a
stand-in.

## 1. A speed modifier on a player (2026-09-11)

**Wanted.** The design says cold slows you a little, and an empty hunger
bar stops you sprinting. Neither is expressible.

**Why the mod cannot do it.** A player's body is stepped from their own
inputs and their entity mirror is overwritten every tick; `game.set_entity`
on it does nothing and `drive` is not read for players. There is no way to
scale a player's walk or sprint speed, or to refuse the sprint gait.

**Ask.** `game.set_player_movement(uuid, { speed = 0.85, sprint = false })`,
a multiplier on the gait speeds and a flag on whether the sprint key does
anything, replaced whole each call like `set_hud`. Predicted on the client
as the ordinary correction already is. Until then cold and hunger cost food
and show on the HUD, and nothing else.

## 2. Setting the time of day (2026-09-11)

**Wanted.** Sleeping in a bed at night should wake you at dawn. The classic
comfort of a night skipped.

**Why the mod cannot do it.** `game.time_of_day()` reads; nothing writes.
The sky is `core_sky`'s registration and the clock is the engine's.

**Ask.** `game.set_time_of_day(t)`, refused outside a tick and outside a
frozen world. The mod's sleep already heals, clears afflictions and sets
home; with this it would also end the night when every player present is
in a bed.

## 3. A line of text to one player (2026-09-11)

**Wanted.** "You cannot sleep now", "you ate an apple", "you died".

**Why the mod cannot do it.** The stubs' `open_container` example calls
`game.chat_to(player, text)`, but no such function is registered: chat is
engine-native and one-directional from players. The mod sends the text as a
HUD value and its HUD script draws it as a toast, cleared by the server a
few seconds later, which works but costs a HUD script for something a
vanilla client could show in the chat pane.

**Ask.** `game.chat_to(uuid, text)`: a server line in that one player's
chat, attributed to the mod. The example in the stubs already promises it.

## 4. A dropped stack keeps its `detail` (2026-09-11)

**Seen.** `game.spawn_entity{ item = ... }` reads `material`, `units`/`count`
and `shape`, and drops `detail`. A named sword dropped on death comes back
as a plain sword and merges with the others.

**Ask.** Read `detail` in the item spec, the way `game.give` does. One field.

## 5. What a player is looking at, server-side (2026-09-11), PARTLY LANDED 2026-09-17 as `game.register_on_use`: using a bed with the place control now sleeps in it; a campfire will cook the same way. Still open for anything that is not a click on a block.

**Wanted.** Use-on-block: X while looking at a bed sleeps in that bed, X
while looking at a campfire cooks what you hold. The HUD script gets
`state.looking_at`; the server does not.

**Why the mod cannot do it.** The sleep finds a bed by scanning the blocks
around the feet, which is fine for a bed and wrong for a campfire three
blocks away that the player is pointing at. `game.entity(body).facing` gives
the direction; walking a ray along it in Lua is per-sample work at the wrong
altitude.

**Ask.** `game.looking_at(uuid)` answering the same `{ x, y, z, material }`
the client already computes for the dig target, or nil.

## 6. Content hashes for a mod's own pictures (2026-09-11), LANDED 2026-09-17 as `game.register_picture` and `game.content_hash`; every HUD icon is registered in items.lua, and the hasher stays for the script's own table

**Wanted.** Hearts and drumsticks as PNGs drawn with `hud.image`.

**Why the mod cannot do it.** `hud.image` takes a 64-hex content hash, which
is `blake3("tiamot:content:v1" .. bytes)`. A mod has no way to compute that
at load and no way to ask for it, so the hash has to be pasted into the
script by hand and re-pasted whenever the picture changes (which is what
`tiamot_inventory` does). This mod draws its icons as rectangles instead.

**Ask.** `game.content_hash("textures/heart.png")` at registration, or a
`hash = game.picture("textures/heart.png")` that both registers the file for
serving and answers its hash, so a HUD script can be given it through
`set_hud` or a generated constant.

## 7. Submersion and fall state on a player's mirror (2026-09-11)

**Seen.** The physics knows a body's submerged fraction and whether it just
landed (it plays `engine:land`). The mirror exposes `on_ground` and
`velocity`, so the mod re-derives both: fluid depth in the head's block
against the eye height every fourth tick, and a fall from the highest point
since the feet left the ground gated on the impact velocity. It works, and
it is a second copy of an answer the engine already has.

**Ask.** `submerged` (0..1) and `fell` (blocks, on the tick of landing) on
the entity table `game.entity` returns for players. Two fields, read from
what the step already computed.
