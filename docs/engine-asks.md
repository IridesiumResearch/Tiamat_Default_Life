# Engine asks from the Life mod

What the survival layer has needed from the engine, found by building it.
Each entry says what was wanted, why the mod cannot do it, and the smallest
engine change that would. Newest first. Landed items stay here, marked, as
the record; the open ones are copied to the engine repo (see below).

## Where these stand (2026-09-26)

**One is open: 18.** Everything else landed, and the mod uses every answer: 17 landed 2026-09-26
(engine 50462b7) as `game.register_on_use_entity`, and the farm's husbandry is built on it.
One thing landed that was never numbered: the place control at nothing (open sky, or a
block past reach) reaches a mod that asks, engine a6d34e1 (protocol 76), so food is eaten
with the right mouse wherever you look. Open asks are
copied, without the history, to the engine's
`docs/engine-asks/tiamat_default_life.md`, so the engine side finds every
mod's open asks in one place. This file keeps everything, landed items
included.

| Item | State | In this mod |
|---|---|---|
| 18 riding | **Open.** | the horse is in the world and cannot be ridden. |
| 17 using an entity | Landed, engine 50462b7. | feeding, milking, shearing and leading, in husbandry.lua. |
| (unnumbered) a use at nothing | Landed, engine a6d34e1, protocol 76. | `hooks.lua` registers `on_use` with `{ anywhere = true }`; right mouse eats what is held at open sky too. |
| 16 a model's skin is not drawn | Landed, engine b5ed249. | every animal painted, first world or fifth; checked by replaying the rejoin through the engine's renderer. |
| 15 a picture over an entity | Landed, engine e5c0394 and 9c4e120. | `game.show_over`: one row of hearts, not sixty-five particles. |
| 14 a mob's own speed | Landed, engine 033f4e6. | `speed` on the entity, scaled off the gait it walks in. |
| 13 a mod's model casts no shadow | Landed, engine 7c0679c. | nothing to do; the cow has a shadow. |
| 12 `steer_entity` jumps at one-cell rises | Landed, engine aa77731. | walkers are steered by the engine again. |
| 11 `fell` counts a flight down | Landed, engine 990bf8a. | the landing-speed gate is gone; `fell` alone decides. |
| 10 key gates | Landed, engine 990bf8a: `wind_sky`, and the debug keys on F-keys. | admins and creative worlds may wind the sky; nobody else. |
| 0 models, step 2 (a texture) | Landed, engine adf6547, with the drawing of mod models at all. | the cow wears `models/cow.png`. |
| 0 models, steps 1 and 3 | Landed, engine 15302d1. | the cow is a cow, with its own clips; other kinds keep the stand-in. |
| 1 and 9 speed, sprint, flight | Landed, engine dc3b5ee and 82444e7. | cold slows, an empty stomach walks, a creative world flies. |
| 2 time of day | Landed, engine eab4c2d. | a night everyone sleeps through ends at dawn. |
| 3 `chat_to` | Landed, engine a3db9fa. | answers to chat words and their refusals are chat lines. |
| 4 `detail` on a dropped stack | Landed, engine a3db9fa. | nothing to change. |
| 5 looking at | Landed, engine a3db9fa. | X sleeps in the bed you look at. Cooking on a campfire is next. |
| 7 `submerged` and `fell` | Landed, engine a3db9fa. | the head-block probe and the peak tracker are gone. |
| 8 operators | Landed, engine a3db9fa. | admins ARE operators; the mod's list and `op`/`deop` are gone. |
| 6 picture hashes | Landed 2026-09-17. | every HUD icon is registered. |

## 18. Riding: a player seated on an entity, driving it (2026-09-23): OPEN

**Wanted.** Right-click a horse and you are on it: sat on its back, the
camera up where a rider's eyes are, your movement keys driving the horse at
the horse's pace, and the use (or sneak) control to get off. The designer
asked for exactly that.

**Why the mod cannot do it.** Nothing seats a player on anything. The
workarounds are all the rubber-banding kind the brief warns against:
`move_player` onto the horse every tick fights the player's own prediction;
`set_entity` on the player's body is overwritten from their inputs the next
tick; dragging the horse under the player with `pos` teleports it and
leaves the player standing inside it with their eyes at their own height.
`set_player_abilities{ speed }` could give the gallop, but not the seat,
the camera or the horse moving as the body.

**Smallest change.** A mount, owned by the engine because it is movement:

```lua
game.mount(player, entity, { seat = { x = 0, y = 1.6, z = 0 } })  -- blocks above the entity's feet
game.dismount(player)                                                -- or nil to ask
game.mounted(player)   --> entity id | nil
```

While mounted, the player's walk/jump/sprint intent drives the ENTITY (its
`speed`, collider and step, predicted on the client as a player's body is),
the player's body rides at the seat and turns with it, and the camera sits
at the seat plus eye height. Sneak dismounts by default, and
`register_on_dismount` (or a field on the event of whatever dismounted
them) lets the mod say where they land. A mount that is despawned or dies
drops its rider.

## 17. Using an entity: right-click on a mob (2026-09-23): LANDED, engine 50462b7

**Landed 2026-09-26** as `game.register_on_use_entity(fn(e))`, `e = { player,
target, owner, held }`, the same ladder as `on_use`, asked before `on_use`
with the server casting the reach ray against the entities' boxes; and
`game.looking_at` answers `{ domain, entity, owner }` when that is what the
crosshair is on. hooks.lua wraps it as `tdl.on_use_entity`; husbandry.lua
feeds, milks, shears and leads through it.

**Wanted.** The place control on an animal does something: get on a horse,
later milk a cow, shear a sheep, feed a pig.

**Why the mod cannot do it.** `register_on_use` fires only at a BLOCK in
reach, and `register_on_punch` only for the dig control. An entity under
the crosshair is invisible to the place control: the use either falls
through to the block behind it or, against the sky, to nothing at all.
Casting a ray in Lua from `look_direction` against every mob's box is the
per-sample work at the wrong altitude that the brief says `looking_at`
exists to prevent.

**Smallest change.** The punch event's twin, for the place control:

```lua
game.register_on_use_entity(function(e)
    -- e.player, e.target (entity id), e.owner (a player's UUID if it is one),
    -- e.held (what is in the hand, as on_use has it)
    return ""        -- handled: the same return ladder as register_on_use
end)
```

fired when the place control is pressed with an entity nearer than any
block along the player's own reach ray, before `on_use` (which then does not
fire). And `game.looking_at` answering an entity when that is what the
crosshair is on, as `{ entity = id }`, so the between-events question has
the same answer.

## 16. A mod's model is drawn matte white though its skin arrives (2026-09-23, cause found 2026-09-24): LANDED, engine b5ed249

**Seen.** In play, every animal is drawn matte white: the rig lit and
shadowed and no colour at all. "Again": they can be right on a first visit
and white after that.

**Cause, reproduced.** The renderer outlives a connection, and
`Renderer::clear_models` ("a model belongs to the server that pushed it")
has no caller. So on a second join (a new world, or back in after the menu)
the renderer still holds last visit's passes. The cache is warm now, and a
warm cache hands the skins over BEFORE the models (every skin first, in a
real server-and-client run on this mod set). Each skin therefore lands on
the OLD pass (`set_model_texture` finds it and sets it there); then the
model arrives and `add_model` builds a fresh pass and inserts it over the
old one, with no skin waiting in `figures.skins` because none was held. A
white pass, for every model, for the rest of the session.

Checked from this side, through the engine's own crates (a scratch program
outside the engine repo, `client` and `server` as path dependencies):

- the client's renderer draws the horse brown with its skin, white without,
  in Simple, Classic and Beautiful, skin-then-model or model-then-skin;
- a real `ServerHandle` on the real mod set, with a real `Connection`, cold
  cache and warm, delivers all eight models and all eight skins with the
  right colours;
- the same renderer given a first visit (model, skin) and then a rejoin
  (skin, model) draws the horse white in every lighting mode: the bug.

**Smallest change.** Call `renderer.clear_models()` when a connection ends
or a new one begins, which is what its own doc says should happen. And, so
a re-sent table can never do this either, have `add_model` keep a skin the
pass it replaces was wearing when none is waiting (or have
`set_model_texture` always remember the last skin per id, rather than
remembering it only while no pass exists). A screenshot test of the rejoin
order would have caught it; `connection.rs` proves a skin arrives, and
nothing proved it is drawn.

**Landed 2026-09-24, engine b5ed249**, both halves: a connection's end
forgets its models, and the renderer keeps the last skin per id whether or
not a pass exists. Replayed here through the fixed engine (first visit,
then a rejoin, skin before model): the horse is brown in Simple, Classic
and Beautiful, where it was white.

## 15. A picture over an entity (2026-09-22): LANDED, engine e5c0394 (a picture on a particle) and 9c4e120 (`game.show_over`)

**Wanted.** Hit a cow and a row of hearts shows over it for a second,
draining. The designer asked for exactly that.

**Why the mod cannot do it properly.** Nothing puts a picture in the world
over an entity: a nametag is text, set only at spawn; the HUD script has
no camera, so it cannot place anything over a thing in the world; a
particle is a flat square of one colour.

**What the mod does now.** Draws each heart in pixels, one particle per
pixel (13 a heart, 65 for a cow), each with no speed, spread or gravity so
it stays put, sent only to the hitter and turned square to them. It works,
and it is 65 messages a blow for what is one picture.

**Smallest change.** Either `texture` on `emit_particles` (a registered
picture, so a heart is one particle), or `game.show_over(entity, { picture,
count, seconds, player })`, a row of icons billboarded over an entity that
follows it. The first is general; the second is what health bars, "!"
over a startled animal and quest markers all are.

## 14. A mob's own speed (2026-09-22): LANDED, engine 033f4e6, as `speed` on the entity

**Seen.** Cows and pigs walked at a player's walk, 4.3 yards a second, and
fled at a player's sprint, 5.6: two to four times what an animal should. A mob's `drive` has gaits and nothing
else, `Intent::walk` is normalised, so a shorter drive is not a slower one,
and `set_player_abilities`' `speed` is for players.

**What the mod does now.** A kind names `walk_speed` and `run_speed` in
blocks a second (the cow and pig: 1.1 and 2.8), drives nothing, and sets
its horizontal velocity to the speed times a gain it nudges each tick by
what the body did. Through `phys::step` on flat ground it settles on
exactly the speed asked, steadily (the gain lands on 1/0.7, the ground
friction). It works; it is a controller standing in for a number, and it
bypasses the gaits a mob was meant to use.

**Smallest change.** `speed` on `drive` (or on the entity), the multiplier
`Abilities::speed` already is for players, through `Abilities::tuning`.

## 13. A mod's model casts no shadow (2026-09-22): LANDED, engine 7c0679c

**Seen, in play.** "The 3d models do not cast shadows." The cow and the pig
float on the ground while the players beside them are anchored by theirs.

**Why.** `Renderer::draw_shadow_casters` draws the engine's own rig
(`self.skinned`) into every cascade, and the models a mod pushed live in
`figures.passes` and are never drawn there. The comment on that very call
says why it matters: a mob with no shadow floats.

**Smallest change.** Draw each pass in `figures.passes` into the cascades
with `skinned_shadow`, as `self.skinned` is. Nothing for a mod to do.

## 12. `steer_entity` jumps at every rise the physics would climb (2026-09-22): LANDED, engine aa77731

**Seen, in play.** Cows and pigs hop across ordinary ground. The designer:
"cows and pigs should really not jump unless they are stuck in a hole."

**Why.** `path::steer` jumps when the block half a block ahead is not
`passable` and the block over it is standable. `passable` is "no floor
cells", so a block of smooth terrain holding a single cell of floor, a
third-of-a-block lip, counts as an obstacle and is jumped. But the physics
already climbs exactly that: `step_height` is one cell, and
`a_step_up_of_one_subnode_succeeds_and_two_does_not`. On the Spindle's
smooth ground nearly every rise is one cell, so a steered mob jumps at
nearly every rise.

**What the mod does now.** Walkers no longer use `steer_entity`. They set
`drive` toward the target themselves, and jump only when stuck: trying to
walk and not moving for half a second (a hole, a full block ahead). If
three jumps do not free them, they give up on that target. That works, and
it is a second copy of steering the engine meant every mod not to write.

**Smallest change.** Jump only for a rise the step cannot take: the height
of the floor ahead above the feet, in cells, greater than
`tuning.step_height`. A one-cell lip is walked; two cells or a full block
is jumped, as now. Optionally a `jump = "stuck"` mode, for mods that want
the calmer rule.

## 11. `fell` counts a flight down to the ground (2026-09-19): LANDED, engine 990bf8a

**Seen.** `fell` is the descent since the feet last left the ground,
settled on the tick they land, and a flying body's descent is part of it.
So an operator who flies down twenty blocks and touches the grass lands
with `fell = 20`, the same number as somebody who stepped off a cliff.

**What the mod does now.** It keeps its own last-tick vertical speed and
only hurts a landing that was moving down fast. That is a reconstruction
of "were they flying", which the engine knows exactly: flight is an intent
it steps with.

**Smallest change.** Accrue nothing while the body is flying (the fall
starts when flight stops), or say `flying` on the entity table beside
`on_ground`. The first keeps `fell` meaning "fell"; the second lets a mod
decide.

## 10. The sky keys need a permission; the debug keys only need to move (2026-09-18, revised): LANDED, engine 990bf8a

*Revised after the engine's answer. The first draft asked for operator gates
on all of these, which was plumbing for nothing: a control that cannot move
your body or change the world needs no permission.*

**10a. The sky keys are a cheat, and unbinding them is not a fix.**
`engine:time_back` / `time_forward` / `time_resync` wind the player's OWN
sky. Nothing on the server changes, but the client draws stored sunlight
scaled by the sky's intensity, so winding to noon lights the player's
night: seeing in the dark for free, in a survival or a one-life world.
Taking the default keys away does nothing, since anybody can bind them
again. **Ask:** a server permission, decided where flight is: the server
tells the client whether this player may wind the sky, and a client that
may not ignores the action whatever it is bound to.

**10b. The rest just move off the letters.** `teleport_far` /
`teleport_home` shift the render origin for the floating-point check and do
not move the body; `material_row` is singleplayer-only already;
`chunk_borders` draws lines. None is a cheat. They hold Y, H, G and B,
which are keys a game wants (this mod had to move its wardrobe off G).
**Ask:** defaults on function keys only (F4 chunk borders, F9 material row,
F7/F8 teleports with no letter twins). No permission.

The first draft, kept for the record of what was seen:

## 10 (first draft). Gates on the engine's own power keys (2026-09-18)

**Seen.** Flight is operator-only and server-enforced, which is right. The
rest of the engine's debug controls are not gated at all, and sit on prime
letter keys:

- `engine:time_back` / `time_forward` / `time_resync` (`[`, `]`, `\\`, and
  PageDown, PageUp, Home) wind the player's OWN sky. Nothing on the server
  changes, but the client draws stored sunlight scaled by the sky's
  intensity, so winding to noon lights the player's night: seeing in the
  dark for free, in a survival or a one-life world.
- `engine:teleport_far` / `teleport_home` (F8, F7, and the letter twins Y,
  H) shift the render origin for the floating-point check. The body does
  not move, so it is not a cheat, but it is a debug control on Y and H.
- `engine:material_row` (G) is singleplayer only already; `chunk_borders`
  (B) is harmless. Both hold letters a game wants (this mod had to move its
  wardrobe off G).

**Why the mod cannot do it.** The engine owns bindings (charter rule 11); a
mod cannot move one, hide one, or put a permission on one.

**Ask.** The sky keys honoured for operators only, decided where flight is
(the server says whether this player may, the client asks). The debug
teleport and the material row for operators or debug builds only. Letter
defaults dropped from all of them: F4 for chunk borders, F9 for the
material row, no letter twins for the teleports. A control a player may not
use left out of their settings screen rather than offered and refused. The
full table is in `docs/controls.md`.

## 9. Abilities a mod grants a player (2026-09-18): LANDED, engine dc3b5ee

**Wanted.** A Creative world where everybody flies. Flight is a PERMISSION
held by the server's operator list, and a mod has no hand on it: a creative
world on a dedicated server has grounded builders unless the host makes
every one of them an operator, with everything else that implies.

**Ask.** `game.set_player_abilities(uuid, { fly = true })`, replaced whole
like `set_hud`, forgotten on leave, OR-ed with the operator list. The same
call is where item 1's speed modifier and sprint flag belong.

**The constraint the engine named, and it is the whole design.** The
client PREDICTS its own movement. If the server scales a player's speed or
grants flight and the client does not know, the two disagree every tick
and the player rubber-bands for as long as the ability lasts. So an
ability is not server state a mod pokes; it is a MESSAGE: the server sends
the player's current abilities (`fly`, `speed`, `sprint`) whenever they
change, the client predicts with exactly those numbers, and the server
steps the body with the same ones. One call for the mod, one message on
the wire, one set of numbers on both ends. Items 1 and 9 are this one
mechanism and should land together.

## 8. Asking who is an operator (2026-09-18): LANDED, engine a3db9fa

**Wanted.** This mod's admin powers (indestructible, `tp`, `revive`, the
testing words) belong to the people the server already trusts.

**Why the mod cannot do it.** The operator list lives in `server.toml` and
the embedded host's identity; nothing in the mod API reads it. So the mod
keeps a second list in its own storage, bootstrapped the way the engine's
is (the first player ever to join is the admin), with `op` and `deop` to
change it. Two lists that mean the same thing will one day disagree.

**Ask.** `game.is_operator(uuid)`. With it the mod's list goes away.

## 0. Models a mod ships (2026-09-11): LANDED, engine 15302d1 (steps 1 and 3) and adf6547 (step 2)

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
   through the existing reader and drawing `tiamat_default_life:cow` where
   it now draws nothing. Clips matched to `AnimTag` by name: `idle`,
   `walk`, `run`, `swing`, `swim`, `sneak`; a missing clip falls back to
   `idle`; no clips at all is a rigid model, still drawn.
2. `texture = "textures/cow.png"` on the same call: one image, sampled by
   the mesh's own UVs, pushed separately as block textures are (which is
   why the reader refuses embedded images). Untextured stays matte white.
3. `scale = 3.0`: the reader takes model space in cells, and a model built
   at one unit to the yard needs a factor rather than a re-export.

*Landed 2026-09-19 (engine 15302d1): step 1 with step 3's `scale` on the
same call, and clips matched by name as asked. The cow is registered and
drawn as itself. Step 2 is what remains: the engine's skinned shader draws
every model matte white, and `register_model` refuses a `texture` field.*

Until 1 lands, every mob is a white humanoid or invisible, and the mob
work goes ahead on behaviour, spawning and drops with the humanoid as a
stand-in.

*The engine's note, 2026-09-18: `fuzz/gltf_ingest` already exists and is in
the CI smoke job, so charter rule 14's requirement (a fuzz target in the
same task as the parser) is already met for step 1. What remains is
wiring, not a new hostile-input surface: a registration, a table sent on
join like the picture table, and a client that loads what arrives.*

## 1. A speed modifier on a player (2026-09-11): LANDED with 9, engine dc3b5ee

**Wanted.** The design says cold slows you a little, and an empty hunger
bar stops you sprinting. Neither is expressible.

**Why the mod cannot do it.** A player's body is stepped from their own
inputs and their entity mirror is overwritten every tick; `game.set_entity`
on it does nothing and `drive` is not read for players. There is no way to
scale a player's walk or sprint speed, or to refuse the sprint gait.

**Ask.** A speed multiplier on the gaits and a flag on whether the sprint
key does anything, as fields of item 9's `set_player_abilities` rather than
a call of their own. **Not** "predicted as the ordinary correction is", as
the first draft said: a correction every tick is rubber-banding. The
numbers travel to the client, which predicts with them; see item 9. Until
then cold and hunger cost food and show on the HUD, and nothing else.

## 2. Setting the time of day (2026-09-11): LANDED, engine eab4c2d

**Wanted.** Sleeping in a bed at night should wake you at dawn. The classic
comfort of a night skipped.

**Why the mod cannot do it.** `game.time_of_day()` reads; nothing writes.
The sky is `core_sky`'s registration and the clock is the engine's.

**Ask.** `game.set_time_of_day(t)`, refused outside a tick and outside a
frozen world. The mod's sleep already heals, clears afflictions and sets
home; with this it would also end the night when every player present is
in a bed.

## 3. `game.chat_to` is documented and does not exist (2026-09-11): a BUG, confirmed by the engine 2026-09-18, FIXED in engine a3db9fa

The engine's own stub calls `game.chat_to(event.player, "somebody is using
that")` in the worked example under `game.open_container`, and no such
function is registered. `scripts/check-stubs.sh` catches a registered
function the stubs omit, and has no eye for the reverse: a call inside a
doc comment to something that was never there.

**Wanted.** "You cannot sleep now", "you ate an apple", "you died".

**Why the mod cannot do it.** The stubs' `open_container` example calls
`game.chat_to(player, text)`, but no such function is registered: chat is
engine-native and one-directional from players. The mod sends the text as a
HUD value and its HUD script draws it as a toast, cleared by the server a
few seconds later, which works but costs a HUD script for something a
vanilla client could show in the chat pane.

**Ask.** `game.chat_to(uuid, text)`: a server line in that one player's
chat, attributed to the mod. The example in the stubs already promises it.

## 4. A dropped stack keeps its `detail` (2026-09-11): LANDED, engine a3db9fa

**Seen.** `game.spawn_entity{ item = ... }` reads `material`, `units`/`count`
and `shape`, and drops `detail`. A named sword dropped on death comes back
as a plain sword and merges with the others.

**Ask.** Read `detail` in the item spec, the way `game.give` does. One field.

## 5. What a player is looking at, server-side (2026-09-11): LANDED, engine a3db9fa, as `game.looking_at` (the click half landed 2026-09-17 as `game.register_on_use`)

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
is `blake3("tiamat:content:v1" .. bytes)`. A mod has no way to compute that
at load and no way to ask for it, so the hash has to be pasted into the
script by hand and re-pasted whenever the picture changes (which is what
`tiamat_inventory` does). This mod draws its icons as rectangles instead.

**Ask.** `game.content_hash("textures/heart.png")` at registration, or a
`hash = game.picture("textures/heart.png")` that both registers the file for
serving and answers its hash, so a HUD script can be given it through
`set_hud` or a generated constant.

## 7. Submersion and fall state on a player's mirror (2026-09-11): LANDED, engine a3db9fa

**Seen.** The physics knows a body's submerged fraction and whether it just
landed (it plays `engine:land`). The mirror exposes `on_ground` and
`velocity`, so the mod re-derives both: fluid depth in the head's block
against the eye height every fourth tick, and a fall from the highest point
since the feet left the ground gated on the impact velocity. It works, and
it is a second copy of an answer the engine already has.

**Ask.** `submerged` (0..1) and `fell` (blocks, on the tick of landing) on
the entity table `game.entity` returns for players. Two fields, read from
what the step already computed.
