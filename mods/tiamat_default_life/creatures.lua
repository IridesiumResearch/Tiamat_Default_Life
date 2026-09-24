-- SPDX-License-Identifier: GPL-3.0-only
--
-- The creatures, as data. Every field mobs.lua reads:
--
--   id, name          the kind; `name` is the nametag while models are stand-ins
--   health            points; a fist is one, the reference sword six
--   collider          { width, height } in CELLS (three to a block)
--   speed, speed_fast flyers only, cells per tick; walkers use the engine's gaits
--   flyer             velocity-controlled rather than steered on the ground
--   lands             a flyer that comes down now and then to walk and eat, and
--                     flies again when its pause is over or anyone comes near
--   navigates         a flyer that keeps a flight plan instead of wandering round a
--                     home: crossing, circling, a tree, the ground (see mobs.lua)
--   wary              blocks: sitting in a tree or on the ground, a player nearer
--                     than this is fled from (in the air it is `shy`)
--   flutters          a flyer that never glides: `run` is its flight, `swing` its bite
--   hangs             a flyer that roosts upside down under a ceiling, on its `idle`
--                     clip; on the ground it rests on `sneak` rather than `idle`
--   roost_min, roost_max  ticks a roost lasts
--   flock             spawns and moves as a group behind a leader
--   shy               blocks: a player nearer than this is fled from
--   hostile           { when = "night" | "dark" | "always", sun_max }
--   provoked          leaves you be until you hurt it, then hunts you (a bear)
--   hunt_ticks        how long a hurt one keeps after you (default `mob_hunt_ticks`)
--   bite              { damage, range (blocks), cooldown (ticks), cause }
--   sight             blocks it notices a player from
--   wander_radius, pause_min, pause_max, fly_low, fly_high
--   sound, sound_death, voice_min, voice_max
--   model, texture    files in this mod: a .glb, and the PNG skin it wears
--   walk_speed, run_speed  a walker's own speeds, blocks a second (default: the engine's
--                     walk and sprint, 4.3 and 5.6, which is a player's)
--   grazes            idles with its head down now and then (the `sneak` clip)
--   jumps             "stuck": never jumps at a rise, only hops out of somewhere
--                     it has been stuck (a hole); left out, the engine's steering
--                     jumps whatever the step cannot take
--
-- A flyer with a model plays `swing` for a wingbeat and `run` for a glide
-- with its wings out; on the ground, `walk`, `idle` and `sneak` as a walker.
--   drops             { { item, min, max } }, items of this mod
--   spawn             { biomes = { biome ids } | land = true, ground = { block ids },
--                       time = "day" | "night" | "any", sun_min, sun_max,
--                       group = { min, max }, weight, cap,
--                       distance = { min, max } blocks from the player, if not the usual }
--
-- WHERE a creature appears is its biomes: the world's own answer for the
-- spot, from Tiamat Default World's `biome_under` export, so a creature is
-- seen only where its kind would really live. `land = true` is every
-- surface biome that is dry land (config.lua's `land_biomes`), for what
-- lives anywhere: crows now, night monsters later. The biome lists that
-- several kinds share are in config.lua.
--
-- `ground` is the fallback for a world without that export: the blocks
-- underfoot that stand for the biome (loam and litter are woodland, grass
-- is grassland, snow the highlands). With the world there, the biome alone
-- decides.

local G = "tiamat_default_world:"

-- The cow has a body of its own: models/cow.glb, made by tools/skin_glb.py
-- from the modeller's export, already skinned. Six cells long, 2.5 wide,
-- 5.3 tall to the tips of its horns, feet on y = 0, facing +Z. Clips: idle, walk, run, swing, and the grazing clip under
-- the engine's spare `sneak` tag, since the engine plays six names and no more.
tdl.register_mob{
    id = "cow", name = "Cow", health = 10,
    collider = { width = 2.4, height = 4.5 },
    model = "models/cow.glb", texture = "models/cow.png", grazes = true, jumps = "stuck",
    walk_speed = 1.1, run_speed = 2.8,
    shy = 1.5, sight = 10, wander_radius = 10, pause_min = 60, pause_max = 240,
    sound = "moo", sound_death = "moo", voice_min = 300, voice_max = 1200,
    drops = { { "raw_meat", 1, 3 } },
    -- Open pasture: grassland, river meadows and the moor.
    spawn = { biomes = { "rolling_grasslands", "river_valleys", "heather_moor" }, ground = { G .. "grass" },
              time = "day", sun_min = 12, group = { 2, 4 }, weight = 4, cap = 6 },
}

-- The sheep: models/sheep.glb, from an export that was already skinned.
-- Four cells long, 2.1 wide, 3.8 tall; its grazing clip under `sneak`.
tdl.register_mob{
    id = "sheep", name = "Sheep", health = 8,
    collider = { width = 2.1, height = 3.6 },
    model = "models/sheep.glb", texture = "models/sheep.png", grazes = true, jumps = "stuck",
    walk_speed = 1.0, run_speed = 2.6,
    shy = 2.0, sight = 10, wander_radius = 8, pause_min = 80, pause_max = 300,
    sound = "baa", sound_death = "baa", voice_min = 300, voice_max = 1200,
    drops = { { "raw_meat", 1, 2 } },
    -- Sheep take to the highlands too: grass in the lowlands, snow up in the frost ring.
    -- Hill grazing: the moor, the highlands, the cliff tops, and grassland.
    spawn = { biomes = { "heather_moor", "alpine_highlands", "coastal_cliffs", "rolling_grasslands" },
              ground = { G .. "grass", G .. "snow", G .. "permafrost" },
              time = "day", sun_min = 12, group = { 3, 6 }, weight = 4, cap = 8 },
}

-- The pig: models/pig.glb, from an export that was already skinned, as the
-- bear's was. Four and a half cells long, 1.9 wide, 2.6 tall; its eating
-- clip under `sneak`.
tdl.register_mob{
    id = "pig", name = "Pig", health = 10,
    collider = { width = 2.4, height = 2.5 },
    model = "models/pig.glb", texture = "models/pig.png", grazes = true, jumps = "stuck",
    walk_speed = 1.1, run_speed = 2.8,
    shy = 1.5, sight = 8, wander_radius = 8, pause_min = 40, pause_max = 200,
    sound = "oink", sound_death = "oink", voice_min = 200, voice_max = 800,
    drops = { { "raw_meat", 1, 2 } },
    -- Rooting in woodland and wet ground, as a wild pig does.
    spawn = { biomes = { "temperate_woodlands", "flower_forest", "silverwood", "river_valleys", "peat_fen" },
              ground = { G .. "grass", G .. "loam", G .. "leaf_litter", G .. "mud", G .. "dirt" },
              time = "day", sun_min = 6, group = { 1, 3 }, weight = 3, cap = 6 },
}

-- The horse: models/horse.glb, from an export that was already skinned.
-- Seven cells long, 2.6 wide, 6.6 tall to the tips of its ears; its grazing
-- clip under `sneak` and a rear kick under `swing`. A herd on open grass,
-- skittish and quick to bolt. It cannot be ridden yet: the engine has no
-- event for right-clicking an entity and no way to seat a player on one
-- (docs/engine-asks.md, asks 17 and 18).
tdl.register_mob{
    id = "horse", name = "Horse", health = 15,
    collider = { width = 2.6, height = 5.4 },
    model = "models/horse.glb", texture = "models/horse.png", grazes = true, jumps = "stuck",
    walk_speed = 1.3, run_speed = 5.2,
    shy = 3.0, sight = 12, wander_radius = 14, pause_min = 60, pause_max = 260,
    sound = "snort", sound_death = "snort", voice_min = 400, voice_max = 1600,
    drops = { { "raw_meat", 1, 3 } },
    -- Wide open grass: grassland, river meadows, the moor.
    spawn = { biomes = { "rolling_grasslands", "river_valleys", "heather_moor" }, ground = { G .. "grass" },
              time = "day", sun_min = 12, group = { 2, 5 }, weight = 2, cap = 6 },
}

-- The goat: a wild mountain goat, horns swept back. models/goat.glb, from an
-- export that was already skinned: four cells long, 4.5 tall to the horn
-- tips, its grazing clip under `sneak` and a head butt under `swing`. It
-- lives on rock and heights, so it keeps the engine's steering and jumps
-- what it must: a goat is the one grazer that climbs. Butt it and it butts
-- you back, and then loses interest.
tdl.register_mob{
    id = "goat", name = "Goat", health = 10,
    collider = { width = 1.6, height = 3.6 },
    model = "models/goat.glb", texture = "models/goat.png", grazes = true,
    walk_speed = 1.2, run_speed = 4.8,
    provoked = true, hunt_ticks = 100,
    bite = { damage = 3, range = 1.8, cooldown = 30, cause = "were butted by a goat" },
    sight = 10, wander_radius = 12, pause_min = 60, pause_max = 240,
    sound = "bleat", sound_death = "bleat", voice_min = 300, voice_max = 1400,
    drops = { { "raw_meat", 1, 2 } },
    -- Rock and heights: the highlands, the cliff tops, the karst, the mesa.
    spawn = { biomes = { "alpine_highlands", "coastal_cliffs", "karst_towers", "arid_mesa", "badlands" },
              ground = { G .. "snow", G .. "grass" },
              time = "day", sun_min = 10, group = { 2, 4 }, weight = 3, cap = 6 },
}

-- The bear: the woods' own, and nobody's quarry. It ambles, forages with
-- its head down and leaves you be; hurt it and it comes for you, faster
-- than you can walk and slower than you can sprint, and swipes hard. Its
-- body is models/bear.glb, from an export that was already skinned: two
-- blocks long, nearly a block and a half tall, its forage clip under
-- `sneak` and its swipe under `swing`.
tdl.register_mob{
    id = "bear", name = "Bear", health = 30,
    collider = { width = 2.8, height = 4.4 },
    model = "models/bear.glb", texture = "models/bear.png", grazes = true,
    walk_speed = 1.3, run_speed = 4.6,
    provoked = true,
    bite = { damage = 7, range = 2.2, cooldown = 30, cause = "were mauled by a bear" },
    sight = 12, wander_radius = 16, pause_min = 80, pause_max = 300,
    sound = "growl", sound_death = "growl", voice_min = 400, voice_max = 1600,
    drops = { { "raw_meat", 2, 4 } },
    -- Deep woods and the cold forest, and up into the highlands.
    spawn = { biomes = { "temperate_woodlands", "taiga", "redwood_stands", "silverwood", "frostpine_coast",
                         "alpine_highlands" },
              ground = { G .. "loam", G .. "leaf_litter", G .. "snow" },
              time = "any", sun_min = 4, group = { 1, 1 }, weight = 1, cap = 2 },
}

-- The stag: a red deer, antlers and all. models/stag.glb, from an export
-- that was already skinned and is wider across the antlers than it is long,
-- so sized along its body (`--axis z`): 5.5 cells long, 7.8 tall to the
-- antler tips. Its grazing clip under `sneak` and an antler lunge under
-- `swing`. Wary, quick to bolt and fast; it lives in woodland and on the moor.
tdl.register_mob{
    id = "stag", name = "Stag", health = 14,
    collider = { width = 2.2, height = 5.0 },
    model = "models/stag.glb", texture = "models/stag.png", grazes = true, jumps = "stuck",
    walk_speed = 1.4, run_speed = 5.6,
    shy = 8, sight = 16, wander_radius = 16, pause_min = 60, pause_max = 240,
    drops = { { "raw_meat", 2, 3 } },
    spawn = { biomes = { "temperate_woodlands", "flower_forest", "silverwood", "redwood_stands", "taiga",
                         "heather_moor", "river_valleys", "alpine_highlands" },
              ground = { G .. "grass", G .. "loam", G .. "leaf_litter", G .. "snow" },
              time = "any", sun_min = 6, group = { 1, 4 }, weight = 2, cap = 5 },
}

-- Crows: a flock passing over. They come in from far off already flying,
-- cross the country at their own height on a straight-ish line, wheel round
-- a point for a while, settle in a tree (more often after dark) until
-- somebody comes near or they take a notion to go, and now and then come
-- down to walk and peck. Only the leader decides; the flock follows. They
-- fly on out of the world once they are past everyone ("Crow navigation"
-- in mobs.lua, numbers in config.lua). They do not attack: that is for
-- later, and for magic. Its body is
-- models/crow.glb, from an export that was already skinned and exported
-- with its wings spread, so sized along its body (`--axis z`): two cells
-- beak to tail, a block across the wings. Clips: `run` is the glide, wings
-- out; `swing` the wingbeat; `walk` and `idle` on the ground, and its
-- pecking under `sneak`.
tdl.register_mob{
    id = "crow", name = "Crow", health = 3,
    collider = { width = 1.2, height = 1.2 },
    model = "models/crow.glb", texture = "models/crow.png", grazes = true,
    flyer = true, lands = true, flock = true, navigates = true, speed = 0.35, speed_fast = 0.6,
    walk_speed = 0.8,
    shy = 5, wary = 10, sight = 20,
    sound = "caw", voice_min = 100, voice_max = 500,
    drops = {},
    -- Anywhere on dry land.
    spawn = { land = true,
              ground = { G .. "grass", G .. "packed_dirt", G .. "leaf_litter", G .. "dead_wood", G .. "dirt" },
              time = "any", sun_min = 8, group = { 3, 6 }, weight = 3, cap = 12, distance = { 56, 88 } },
}

-- Bats: the dark's own. Caves by day, anywhere by night; they bite and
-- flutter off, and bite again. Its body is models/bat.glb, a skinned export
-- with its wings spread, sized along its body (`--axis z`): a fifth of a
-- block nose to tail and a block and a third across the wings. It flutters
-- on its `run` clip and bites on `swing`. With a ceiling over it, it goes up
-- and hangs there on its `idle` clip; now and then it comes down instead and
-- crawls (`walk`) and eats (`sneak`) on the ground. Anyone it hunts, it lets
-- go for.
tdl.register_mob{
    id = "bat", name = "Bat", health = 3,
    collider = { width = 1.0, height = 1.0 },
    model = "models/bat.glb", texture = "models/bat.png",
    flyer = true, flutters = true, hangs = true, lands = true,
    speed = 0.4, speed_fast = 0.65, walk_speed = 0.3, roost_min = 400, roost_max = 1600,
    sight = 16, wander_radius = 10, fly_low = 2, fly_high = 6,
    hostile = { when = "dark", sun_max = 3 },
    bite = { damage = 1, range = 1.4, cooldown = 30, cause = "were bitten to death by bats" },
    sound = "squeak", voice_min = 60, voice_max = 300,
    drops = {},
    -- The ordinary caves, lit and dark.
    spawn = { biomes = tdl.config.cave_biomes, time = "any", sun_max = 2, group = { 2, 4 }, weight = 3, cap = 6 },
}

return {}
