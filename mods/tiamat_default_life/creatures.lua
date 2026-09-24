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
--   sound, sound_death, voice_min, voice_max   a cue, or a list of cues (takes of one voice)
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
--   spawn             { biomes = { [biome id] = weight } | { biome ids } | land = true, ground = { block ids },
--                       time = "day" | "night" | "any", sun_min, sun_max,
--                       dark = true: at night, or by day where sun <= sun_max (a monster),
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
-- HOW OFTEN is the weight beside each biome: common, uncommon, scarce or
-- rare (config.lua), drawn against every other kind living at that spot.
-- Cattle, pigs and sheep are common across much of the world, each where
-- it fits best; a stag is never better than scarce, and a bear is rarer.
--
-- `ground` is the fallback for a world without that export: the blocks
-- underfoot that stand for the biome (loam and litter are woodland, grass
-- is grassland, snow the highlands). With the world there, the biome alone
-- decides.

local G = "tiamat_default_world:"
local C = tdl.config
local COMMON, UNCOMMON, SCARCE, RARE = C.common, C.uncommon, C.scarce, C.rare

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
    -- Pasture first, and a fair way beyond it; rare up in the mountains.
    spawn = { biomes = {
                  rolling_grasslands = COMMON, river_valleys = COMMON,
                  heather_moor = UNCOMMON, flower_forest = UNCOMMON, savanna = UNCOMMON,
                  temperate_woodlands = SCARCE, peat_fen = SCARCE, coastal_cliffs = SCARCE,
                  alpine_highlands = RARE, mangrove_coast = RARE,
              },
              ground = { G .. "grass" },
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
    -- Hill grazing above all: common on the moor and up in the mountains,
    -- and about the lowland pasture too; never in the jungle or the fen.
    spawn = { biomes = {
                  heather_moor = COMMON, alpine_highlands = COMMON, rolling_grasslands = COMMON,
                  coastal_cliffs = UNCOMMON, river_valleys = UNCOMMON, frostpine_coast = UNCOMMON,
                  flower_forest = SCARCE, rime_tundra = SCARCE, taiga = RARE,
              },
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
    sound = { "oink", "oink_2" }, sound_death = "oink_2", voice_min = 200, voice_max = 800,
    drops = { { "raw_meat", 1, 2 } },
    -- Rooting in wet and wooded ground: commonest in the jungle and the
    -- swamps, common in the woods, about the farmland, never on the heights.
    spawn = { biomes = {
                  jungle = COMMON, peat_fen = COMMON, mangrove_coast = COMMON,
                  temperate_woodlands = COMMON, flower_forest = UNCOMMON, silverwood = UNCOMMON,
                  river_valleys = UNCOMMON, rolling_grasslands = SCARCE, savanna = SCARCE,
                  redwood_stands = SCARCE,
              },
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
    -- Wide open grass, in herds that are a sight rather than a crowd.
    spawn = { biomes = {
                  rolling_grasslands = UNCOMMON, savanna = UNCOMMON,
                  river_valleys = SCARCE, heather_moor = SCARCE,
              },
              ground = { G .. "grass" },
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
    spawn = { biomes = {
                  alpine_highlands = UNCOMMON, karst_towers = UNCOMMON,
                  coastal_cliffs = SCARCE, arid_mesa = SCARCE, badlands = SCARCE, rime_wall = RARE,
              },
              ground = { G .. "snow", G .. "grass" },
              time = "day", sun_min = 10, group = { 2, 4 }, weight = 3, cap = 6 },
}

-- The bunny: a wild rabbit. models/bunny.glb, from an export that was already
-- skinned: a cell and a half long, two tall to the tips of its ears, its
-- nibbling clip under `sneak`. Small, very shy (it bolts at six blocks) and
-- quick, and everywhere there is grass to nibble and cover to run to. It
-- makes no sound; rabbits mostly do not.
tdl.register_mob{
    id = "bunny", name = "Bunny", health = 3,
    collider = { width = 1.0, height = 1.8 },
    model = "models/bunny.glb", texture = "models/bunny.png", grazes = true, jumps = "stuck",
    walk_speed = 0.8, run_speed = 5.0,
    shy = 6, sight = 12, wander_radius = 8, pause_min = 30, pause_max = 160,
    drops = { { "raw_meat", 1, 1 } },
    spawn = { biomes = {
                  rolling_grasslands = COMMON, flower_forest = COMMON, heather_moor = COMMON,
                  temperate_woodlands = UNCOMMON, river_valleys = UNCOMMON, savanna = UNCOMMON,
                  coastal_cliffs = UNCOMMON, sandy_shores = SCARCE, dunes = SCARCE,
                  taiga = SCARCE, alpine_highlands = SCARCE, rime_tundra = SCARCE, silverwood = SCARCE,
              },
              ground = { G .. "grass", G .. "dirt", G .. "snow" },
              time = "day", sun_min = 8, group = { 1, 3 }, weight = 4, cap = 6 },
}

-- The fox: models/fox.glb, from an export that was already skinned. A cell
-- over a block long with its brush, its nosing clip under `sneak`. Shy, and
-- about at any hour, as foxes are: dusk and dawn most of all.
tdl.register_mob{
    id = "fox", name = "Fox", health = 6,
    collider = { width = 1.0, height = 2.2 },
    model = "models/fox.glb", texture = "models/fox.png", grazes = true, jumps = "stuck",
    walk_speed = 1.2, run_speed = 5.2,
    shy = 7, sight = 14, wander_radius = 16, pause_min = 40, pause_max = 200,
    sound = "yip", sound_death = "yip", voice_min = 600, voice_max = 2400,
    drops = { { "raw_meat", 1, 1 } },
    spawn = { biomes = {
                  temperate_woodlands = UNCOMMON, flower_forest = UNCOMMON, heather_moor = UNCOMMON,
                  rolling_grasslands = SCARCE, river_valleys = SCARCE, silverwood = SCARCE,
                  taiga = SCARCE, frostpine_coast = SCARCE, rime_tundra = RARE, dunes = RARE,
              },
              ground = { G .. "grass", G .. "loam", G .. "leaf_litter", G .. "snow" },
              time = "any", sun_min = 6, group = { 1, 2 }, weight = 2, cap = 3 },
}

-- The squirrel: models/squirrel.glb, from an export that was already
-- skinned. The smallest thing in the world, under half a block with its
-- tail. Quick and nervy, in the forests only; silent (the library has no
-- squirrel).
tdl.register_mob{
    id = "squirrel", name = "Squirrel", health = 2,
    collider = { width = 0.6, height = 0.9 },
    model = "models/squirrel.glb", texture = "models/squirrel.png", grazes = true, jumps = "stuck",
    walk_speed = 1.0, run_speed = 5.0,
    shy = 5, sight = 10, wander_radius = 6, pause_min = 20, pause_max = 120,
    drops = {},
    spawn = { biomes = {
                  temperate_woodlands = COMMON, silverwood = COMMON, flower_forest = UNCOMMON,
                  redwood_stands = UNCOMMON, taiga = UNCOMMON, frostpine_coast = SCARCE, jungle = SCARCE,
              },
              ground = { G .. "loam", G .. "leaf_litter", G .. "grass" },
              time = "day", sun_min = 4, group = { 1, 2 }, weight = 3, cap = 6 },
}

-- The wolf: models/wolf.glb, from an export that was already skinned, a
-- block and a half long, its sniffing clip under `sneak` and a lunge under
-- `swing`. It lives in the cold forests and the highlands in packs of two
-- to four, leaves you be, and like the bear turns on whoever hurts it.
-- Its voice is a dog's bark from the library until there is a howl.
tdl.register_mob{
    id = "wolf", name = "Wolf", health = 14,
    collider = { width = 1.5, height = 3.2 },
    model = "models/wolf.glb", texture = "models/wolf.png", grazes = true,
    walk_speed = 1.4, run_speed = 5.4,
    provoked = true, hunt_ticks = 300,
    bite = { damage = 4, range = 1.8, cooldown = 24, cause = "were brought down by a wolf" },
    sight = 14, wander_radius = 20, pause_min = 60, pause_max = 240,
    sound = "bark", sound_death = "bark", voice_min = 800, voice_max = 3000,
    drops = { { "raw_meat", 1, 2 } },
    spawn = { biomes = {
                  taiga = UNCOMMON, frostpine_coast = UNCOMMON, alpine_highlands = SCARCE,
                  rime_tundra = SCARCE, redwood_stands = SCARCE, frozen_wastes = RARE, temperate_woodlands = RARE,
              },
              ground = { G .. "snow", G .. "permafrost", G .. "loam", G .. "leaf_litter" },
              time = "any", sun_min = 4, group = { 2, 4 }, weight = 1, cap = 4 },
}

-- The mammoth: models/mammoth.glb, from an export that was already skinned,
-- four blocks long and three tall, its foraging clip under `sneak` and a
-- tusk swing under `swing`. The frozen north's, slow, rare, and a very bad
-- thing to have hurt. It trumpets: an elephant's take from the library.
tdl.register_mob{
    id = "mammoth", name = "Mammoth", health = 60,
    collider = { width = 5.0, height = 8.4 },
    model = "models/mammoth.glb", texture = "models/mammoth.png", grazes = true, jumps = "stuck",
    walk_speed = 1.0, run_speed = 3.6,
    provoked = true, hunt_ticks = 200,
    bite = { damage = 9, range = 3.2, cooldown = 40, cause = "were trampled by a mammoth" },
    sight = 14, wander_radius = 24, pause_min = 100, pause_max = 400,
    sound = "trumpet", sound_death = "trumpet", voice_min = 1200, voice_max = 4000,
    drops = { { "raw_meat", 4, 8 } },
    spawn = { biomes = {
                  frozen_wastes = SCARCE, rime_tundra = SCARCE, icefall = RARE, rime_wall = RARE,
              },
              ground = { G .. "snow", G .. "permafrost" },
              time = "day", sun_min = 6, group = { 1, 3 }, weight = 1, cap = 3 },
}

-- The spider: models/spider.glb, from an export that was already skinned
-- and wider across its legs than it is long (`--axis z`): a block and a
-- third across, its feeding clip under `sneak` and a strike under `swing`.
-- The first monster. It appears only in the dark: on any land at night, and
-- in the caves at any hour. It hunts whoever it sees in the dark and bites
-- for 2; in daylight it leaves you be.
tdl.register_mob{
    id = "spider", name = "Spider", health = 12,
    collider = { width = 3.0, height = 1.6 },
    model = "models/spider.glb", texture = "models/spider.png", grazes = true,
    walk_speed = 1.4, run_speed = 4.8,
    hostile = { when = "dark", sun_max = 3 },
    bite = { damage = 2, range = 1.8, cooldown = 30, cause = "were bitten by a spider" },
    sight = 16, wander_radius = 12, pause_min = 40, pause_max = 200,
    sound = { "hiss", "hiss_2" }, sound_death = "hiss", voice_min = 300, voice_max = 1200,
    drops = {},
    spawn = { land = true, biomes = C.cave_biomes, dark = true, sun_max = 3,
              time = "any", group = { 1, 2 }, weight = 3, cap = 6 },
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
    sound = { "growl", "growl_2", "growl_3" }, sound_death = "growl_3", voice_min = 400, voice_max = 1600,
    drops = { { "raw_meat", 2, 4 } },
    -- Deep woods and the cold forest, and up into the highlands.
    spawn = { biomes = {
                  taiga = SCARCE, redwood_stands = SCARCE,
                  temperate_woodlands = RARE, silverwood = RARE, frostpine_coast = RARE, alpine_highlands = RARE,
              },
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
    sound = "bell", sound_death = "bell", voice_min = 600, voice_max = 2400,
    drops = { { "raw_meat", 2, 3 } },
    -- A deer is a thing you are lucky to see: scarce at best.
    spawn = { biomes = {
                  temperate_woodlands = SCARCE, silverwood = SCARCE, redwood_stands = SCARCE, taiga = SCARCE,
                  flower_forest = RARE, heather_moor = RARE, river_valleys = RARE, alpine_highlands = RARE,
              },
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
    sound = { "caw", "caw_2" }, voice_min = 100, voice_max = 500,
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
    sound = { "squeak", "squeak", "flap" }, voice_min = 60, voice_max = 300,
    drops = {},
    -- The ordinary caves, lit and dark.
    spawn = { biomes = tdl.config.cave_biomes, time = "any", sun_max = 2, group = { 2, 4 }, weight = 3, cap = 6 },
}

return {}
