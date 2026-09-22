-- SPDX-License-Identifier: GPL-3.0-only
--
-- The creatures, as data. Every field mobs.lua reads:
--
--   id, name          the kind; `name` is the nametag while models are stand-ins
--   health            points; a fist is one, the reference sword six
--   collider          { width, height } in CELLS (three to a block)
--   speed, speed_fast flyers only, cells per tick; walkers use the engine's gaits
--   flyer             velocity-controlled rather than steered on the ground
--   flock             spawns and moves as a group behind a leader
--   shy               blocks: a player nearer than this is fled from
--   hostile           { when = "night" | "dark" | "always", sun_max }
--   bite              { damage, range (blocks), cooldown (ticks), cause }
--   sight             blocks it notices a player from
--   wander_radius, pause_min, pause_max, fly_low, fly_high
--   sound, sound_death, voice_min, voice_max
--   model, texture    files in this mod: a .glb, and the PNG skin it wears
--   walk_speed, run_speed  a walker's own speeds, blocks a second (default: the engine's
--                     walk and sprint, 4.3 and 5.6, which is a player's)
--   grazes            idles with its head down now and then (the `sneak` clip)
--   drops             { { item, min, max } }, items of this mod
--   spawn             { ground = { block ids }, rings = { ring ids }, time = "day" | "night" | "any",
--                       sun_min, sun_max, group = { min, max }, weight, cap }
--
-- The engine has no biome to ask about, so a biome is two things here: the
-- RING of the Spindle the spot is in, by radius (config.lua carries the
-- world's ring table), and the block under the feet, which is what the
-- biome within the ring is made of (loam and litter are woodland; dirt
-- under grass is grassland; snow is the highlands).

local G = "tiamot_default_world:"

-- The cow has a body of its own: models/cow.glb, made by tools/skin_glb.py
-- from the modeller's export. Six cells long, 2.4 wide, 4.6 tall, feet on
-- y = 0, facing +Z. Clips: idle, walk, run, swing, and the grazing clip under
-- the engine's spare `sneak` tag, since the engine plays six names and no more.
tdl.register_mob{
    id = "cow", name = "Cow", health = 10,
    collider = { width = 2.4, height = 4.5 },
    model = "models/cow.glb", texture = "models/cow.png", grazes = true,
    walk_speed = 1.1, run_speed = 2.8,
    shy = 1.5, sight = 10, wander_radius = 10, pause_min = 60, pause_max = 240,
    sound = "moo", sound_death = "moo", voice_min = 300, voice_max = 1200,
    drops = { { "raw_meat", 1, 3 } },
    spawn = { ground = { G .. "grass" }, rings = { "temperate", "verdant", "shore" },
              time = "day", sun_min = 12, group = { 2, 4 }, weight = 4, cap = 6 },
}

tdl.register_mob{
    id = "sheep", name = "Sheep", health = 8,
    collider = { width = 2.1, height = 2.7 },
    shy = 2.0, sight = 10, wander_radius = 8, pause_min = 80, pause_max = 300,
    sound = "baa", sound_death = "baa", voice_min = 300, voice_max = 1200,
    drops = { { "raw_meat", 1, 2 } },
    -- Sheep take to the highlands too: grass in the lowlands, snow up in the frost ring.
    spawn = { ground = { G .. "grass", G .. "snow", G .. "permafrost" }, rings = { "frost", "temperate", "verdant", "shore", "hem" },
              time = "day", sun_min = 12, group = { 3, 6 }, weight = 4, cap = 8 },
}

-- The pig too: models/pig.glb, the same way. Four and a half cells long,
-- 1.9 wide, 2.5 tall, the same rig and the same five clips as the cow.
tdl.register_mob{
    id = "pig", name = "Pig", health = 10,
    collider = { width = 2.4, height = 2.5 },
    model = "models/pig.glb", texture = "models/pig.png", grazes = true,
    walk_speed = 1.1, run_speed = 2.8,
    shy = 1.5, sight = 8, wander_radius = 8, pause_min = 40, pause_max = 200,
    sound = "oink", sound_death = "oink", voice_min = 200, voice_max = 800,
    drops = { { "raw_meat", 1, 2 } },
    spawn = { ground = { G .. "grass", G .. "loam", G .. "leaf_litter", G .. "mud", G .. "dirt" },
              rings = { "temperate", "verdant", "shore" }, time = "day", sun_min = 6, group = { 1, 3 }, weight = 3, cap = 6 },
}

-- Crows: a flock by day, wheeling over the fields and keeping their
-- distance; after dark they mob whoever is out, pecking and wheeling away.
tdl.register_mob{
    id = "crow", name = "Crow", health = 3,
    collider = { width = 1.0, height = 1.0 },
    flyer = true, flock = true, speed = 0.35, speed_fast = 0.6,
    shy = 4, sight = 20, wander_radius = 14, fly_low = 4, fly_high = 12,
    hostile = { when = "night" },
    bite = { damage = 1, range = 1.6, cooldown = 40, cause = "were pecked to death by crows" },
    sound = "caw", voice_min = 100, voice_max = 500,
    drops = {},
    spawn = { ground = { G .. "grass", G .. "packed_dirt", G .. "leaf_litter", G .. "dead_wood", G .. "dirt" },
              rings = { "frost", "temperate", "ember", "verdant", "shore", "hem" },
              time = "any", sun_min = 8, group = { 3, 6 }, weight = 3, cap = 12 },
}

-- Bats: the dark's own. Caves by day, anywhere by night; they bite and
-- flutter off, and bite again.
tdl.register_mob{
    id = "bat", name = "Bat", health = 3,
    collider = { width = 1.0, height = 1.0 },
    flyer = true, speed = 0.4, speed_fast = 0.65,
    sight = 16, wander_radius = 10, fly_low = 2, fly_high = 6,
    hostile = { when = "dark", sun_max = 3 },
    bite = { damage = 1, range = 1.4, cooldown = 30, cause = "were bitten to death by bats" },
    sound = "squeak", voice_min = 60, voice_max = 300,
    drops = {},
    spawn = { time = "any", sun_max = 2, group = { 2, 4 }, weight = 3, cap = 6 },
}

return {}
