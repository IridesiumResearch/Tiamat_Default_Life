-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The crops, as data. Every field farming.lua reads is listed at
-- `tdl.register_crop`; what is here is the six the default world grows, one
-- for each kind of country it has, and where the FIRST seed of each is found
-- is config.lua's `forage`.
--
-- Stages are blocks, drawn from `textures/<id>_<n>.png`, and a crop takes
-- as long as the engine's random tick takes to come round to each of them:
-- more stages is a longer season. Three is a season of about an hour on wet
-- ground; a mushroom has two and comes quickest.

local W = "tiamat_default_world:"

-- Grain for the grasslands. Wheat is feed for the herd and, once there is a
-- mill (Tiamat Default Craft), flour.
tdl.register_crop{
    id = "wheat", name = "Wheat", stages = 3,
    seed = "wheat_seeds", produce = "wheat", produce_min = 1, produce_max = 2, seed_min = 1, seed_max = 2,
    soil = "tilled", light = "sun",
    biomes = { "rolling_grasslands", "river_valleys", "flower_forest", "heather_moor", "savanna", "temperate_woodlands" },
}

-- A root for the cold edge: it does not mind the frost, and is eaten raw.
tdl.register_crop{
    id = "turnip", name = "Turnip", stages = 3,
    seed = "turnip_seeds", produce = "turnip", produce_min = 1, produce_max = 3, seed_min = 1, seed_max = 2,
    soil = "tilled", light = "sun",
    biomes = { "taiga", "rime_tundra", "frostpine_coast", "alpine_highlands", "heather_moor", "temperate_woodlands", "silverwood" },
}

-- Rice, in a paddy: it grows only on WET tilled ground, so a rice field is
-- dug beside the river or in the fen, where the ground never dries.
tdl.register_crop{
    id = "rice", name = "Rice", stages = 3,
    seed = "rice_seeds", produce = "rice", produce_min = 1, produce_max = 3, seed_min = 1, seed_max = 2,
    soil = "wet", light = "sun",
    biomes = { "river_valleys", "peat_fen", "mangrove_coast", "jungle" },
}

-- A melon vine for the jungle: the source of the cool melon.
tdl.register_crop{
    id = "melon", name = "Melon vine", stages = 3,
    seed = "melon_seeds", produce = "cool_melon", produce_min = 1, produce_max = 1, seed_min = 1, seed_max = 3,
    soil = "tilled", light = "sun",
    biomes = { "jungle", "mangrove_coast", "savanna" },
}

-- Mushrooms, on the floor of a dark cave, on the ground fungi grow from.
-- No biome: the dark is what they want, and a cellar is as good as a cave.
tdl.register_crop{
    id = "mushroom", name = "Mushrooms", stages = 2,
    seed = "spores", produce = "mushroom", produce_min = 1, produce_max = 2, seed_min = 1, seed_max = 2,
    soil = { W .. "mycelium", W .. "mulch", W .. "dirt", W .. "black_mud", W .. "moss" }, light = "dark",
}

for _, id in ipairs(tdl.farming.order) do
    tdl.farming.tick_crop(tdl.farming.crops[id])
end

return {}
