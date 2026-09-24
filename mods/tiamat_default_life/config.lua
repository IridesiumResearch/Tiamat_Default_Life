-- SPDX-License-Identifier: GPL-3.0-only
--
-- Every number a designer might want to turn, in one place, in the units the
-- rest of the mod uses: POINTS for health, food and air (27 of each, three to
-- a heart, cookie or bubble) and TICKS for time (20 to a second).
--
-- Nothing here shapes the world, so nothing here is a `game.register_setting`:
-- these are the mod's opinions, read once at load.

local C = {}

-- Chat words for testing ("hurt", "boom", "spawn" and so on; see actions.lua
-- and mobs.lua). They are ADMIN words either way (modes.lua); this switch
-- removes them altogether for a server that wants none of it.
C.dev_commands = true

-- The world's mode: "Default", "Creative" or "Adventure". A world option,
-- picked when the world is made and fixed for its life (mod.toml); an
-- engine from before world options gets Default.
C.mode = "Default"
if game.world_option then
    local chosen = game.world_option(game.mod_id .. ":mode")
    if type(chosen) == "string" then C.mode = chosen end
end

-- Whether one player's punch hurts another.
C.pvp = true

-- Vitals ------------------------------------------------------------------

C.max_health = 27          -- nine hearts of three
C.max_food = 27            -- nine cookies of two, plus nine hidden points of saturation
C.visible_food = 18        -- the cookies show this much; the rest is the buffer
C.max_air = 27             -- nine bubbles of three

-- A new player, and what a respawn gives back.
C.spawn_health = 27
C.spawn_food = 22          -- full cookies and a little saturation
C.respawn_food = 18        -- full cookies, no saturation: eat something

-- Regeneration. With saturation (food above `visible_food`) a heart comes
-- back fast; with the cookies nearly full it comes back slowly; below
-- that, not at all. Every point healed costs food.
C.regen_fast_ticks = 20        -- one point a second while the buffer lasts
C.regen_slow_ticks = 80        -- one point every four seconds on full cookies
C.regen_slow_min_food = 16     -- eight cookies
C.regen_food_cost = 0.4        -- food points per health point healed
C.regen_quiet_ticks = 60       -- no regeneration for three seconds after being hurt

-- Starvation: an empty bar drains health, slowly, and never past a heart.
C.starve_ticks = 80
C.starve_floor = 3

-- Exhaustion: food is spent in fractions and a point comes off when the
-- fraction reaches one. Per tick.
C.exhaust_idle = 0.0006        -- about a point every 80 seconds standing still
C.exhaust_walk = 0.0020        -- walking: 25 seconds a point
C.exhaust_sprint = 0.0050      -- running: 10 seconds a point
C.exhaust_swim = 0.0030
C.exhaust_per_damage = 0.10    -- per point of damage taken
C.exhaust_temperature = 1.5    -- multiplier while too hot or too cold
C.exhaust_rested = 0.7         -- multiplier while well-rested
C.speed_walking = 0.30         -- cells per tick; below is standing (walk is ~0.65)
C.speed_sprinting = 0.72       -- above is running (sprint is ~0.84)
C.low_food = 6                 -- three cookies: "hungry", shown on the HUD

-- Air ---------------------------------------------------------------------

C.air_drain_ticks = 13         -- one point every 0.65 s: about 18 s of breath
C.air_refill_per_tick = 3      -- a whole bubble a tick once the head is out
C.drown_ticks = 20             -- once empty, a heart a second
C.drown_damage = 3

-- Temperature -------------------------------------------------------------
--
-- Body temperature is a number from -1 (frozen) to +1 (cooked), 0 comfortable.
-- The AMBIENT is worked out from the surroundings each sample and the body
-- drifts toward it. Clothing and warm or cold food shift the ambient.

C.temp_sample_ticks = 10
C.temp_drift = 0.04            -- fraction of the gap closed per sample (about 12 s to settle)
C.temp_show = 0.35             -- the thermometer appears past this
C.temp_uncomfortable = 0.55    -- "cold" / "hot": hunger burns faster, and cold slows you
C.cold_speed = 0.8             -- a body this cold or colder moves at this share of its speed
C.temp_extreme = 0.90          -- "freezing" / "overheating": slow damage
C.temp_damage_ticks = 100      -- overheating: a point every five seconds
C.freeze_damage_ticks = 200    -- freezing: a point every ten seconds, slower than heat
C.temp_damage = 1
-- Ambient contributions. They add.
C.temp_night = -0.45           -- under the open sky at night
C.temp_noon = 0.20             -- under the open sky around midday
C.temp_cave = -0.20            -- out of the sun entirely
C.temp_water = -0.60           -- swimming
C.temp_wet = -0.25             -- standing in shallow water
C.temp_clothing = 0.40         -- per warm (or cool) garment worn, up to two
C.temp_food = 0.45             -- a hot stew or a cool melon, while the effect lasts
C.temp_source_radius = 3       -- blocks, for heat and cold sources
C.temp_source_near = 0.75      -- a source within one block
C.temp_source_far = 0.40       -- a source within the radius
-- How far below the open-sky line a body is before "cave" applies.
C.cave_sun_max = 5             -- get_light().sun at the head; 15 is open sky

-- The world's own climate. Tiamat Default World (the Spindle) makes its
-- temperature RADIAL: `T = 4t(1 - t)` in `t = r / R`, cold at the axis,
-- hottest halfway out, cold again at the rim (its docs/spindle-mod-plan.md,
-- C.3). This mod reads nothing of the world's; it does the same sum from
-- the player's position, so the two must be kept in step by hand.
-- Comfortable is the temperate ring, where the world puts a new player.
C.climate = true
C.world_radius = 59000         -- blocks: the Spindle's R_DISC, 59 km
C.climate_comfort = 0.77       -- the T of the spawn plain (t = 0.26)
C.climate_scale = 2.0          -- ambient per unit of T away from comfort
-- The surface rings, by t, from the world's layers.lua. Creatures name the
-- rings they belong to; the temperate ring is where you start.
C.rings = {
    { id = "crown",     t = { 0.00, 0.08 } },
    { id = "frost",     t = { 0.08, 0.18 } },
    { id = "temperate", t = { 0.18, 0.35 } },
    { id = "ember",     t = { 0.35, 0.42 } },
    { id = "glass",     t = { 0.42, 0.48 } },
    { id = "verdant",   t = { 0.48, 0.60 } },
    { id = "shore",     t = { 0.60, 0.85 } },
    { id = "hem",       t = { 0.85, 1.00 } },
}
-- Night, as time_of_day: 0 is midnight, 0.5 noon.
C.night_before = 0.22
C.night_after = 0.78

-- Fire --------------------------------------------------------------------

C.lava_damage = 4              -- per hit, standing in it
C.lava_ticks = 10
C.campfire_damage = 1          -- standing in a campfire
C.campfire_ticks = 20
C.burn_after_lava = 100        -- burning carries on for five seconds after climbing out
C.burn_after_campfire = 40
C.flame_every = 5              -- ticks between bursts of flame over anything burning
-- A creature burned to death leaves its meat cooked.
C.cooked_by_fire = { raw_meat = "cooked_meat" }

-- Falls -------------------------------------------------------------------

C.fall_safe_blocks = 3.0       -- no damage up to this
C.fall_damage_per_block = 1.15 -- past that (1.5 / 1.3: a body 30% tougher than it was)
C.submerged_head = 0.9         -- share of the body in fluid that puts the eyes under (1.62 of 1.8)
C.submerged_swimming = 0.35    -- share that is swimming rather than wading

-- Damage bookkeeping --------------------------------------------------------

C.hurt_cooldown_ticks = 10     -- within it, only the excess over the last hit lands (the classic rule)
C.respawn_invulnerable_ticks = 60
C.knockback = 0.9              -- cells per tick, a punch
C.knockback_up = 0.5

-- Death -------------------------------------------------------------------

C.drop_fraction = 3            -- one in this many of every stack is dropped; the rest is kept
C.respawn_above_bed = 1.0

-- Sleep -------------------------------------------------------------------

C.sleep_any_time = false       -- nights only, like the classics; a bed sets your respawn any time
C.bed_reach = 2                -- blocks
C.sleep_window = 20 * 30       -- ticks: everyone who slept within this has slept tonight
C.wake_time = 0.25             -- the time of day a slept-through night ends at: dawn
C.rested_ticks = 20 * 60 * 5   -- five minutes of well-rested
C.well_fed_ticks = 20 * 60 * 3 -- three minutes after a proper meal

-- Explosions --------------------------------------------------------------

C.explosion_push = 2.5         -- cells per tick at the centre
C.explosion_push_up = 0.8

-- Mobs ---------------------------------------------------------------------

-- A creature with a model of its own (`model` in creatures.lua) is drawn as
-- it. One without is the engine's white humanoid with its kind as a
-- nametag while this is true, and invisible when it is false: the engine
-- draws nothing for a model name nobody registered.
C.placeholder_models = true
C.mob_hearts = true            -- a row of hearts over a mob for the player who hit it
C.mob_hearts_seconds = 1.2     -- how long it shows
C.mob_heart_size = 0.32        -- blocks across, per heart
C.mob_swing_ticks = 20         -- how long a mob plays its swing clip after a blow
C.mob_moving_speed2 = 0.0025   -- (cells per tick)^2; slower than this, a walker trying to go is not going
C.mob_stuck_ticks = 60         -- ticks of trying and not going before it gives up on where it was going
C.mob_hop_ticks = 20           -- a kind that jumps only when stuck: ticks stuck before its one hop
C.mob_arrive = 0.6             -- blocks from where it was going that count as there, for a kind driven here
C.player_walk = 4.3            -- the engine's own gaits, blocks a second: what a kind's
C.player_sprint = 5.6          -- speeds are a multiple of (`speed` on the entity)
C.mob_spawn_every = 100        -- ticks between spawning passes, per player
C.mob_spawn_tries = 6          -- ground spots tried per pass
C.mob_spawn_min = 20           -- blocks from the player, at least
C.mob_spawn_max = 44           -- and at most
C.mob_spawn_far = 88           -- the furthest any kind appears (`spawn.distance`); spots are drawn out to here
C.mob_count_radius = 64        -- how far around a player the caps count
C.mob_cap_total = 32           -- of everything, per player
C.mob_flee_ticks = 100         -- five seconds of running from a hit
C.mob_hunt_ticks = 400         -- twenty seconds of chasing before losing interest
C.fly_lift = 0.24              -- cells per tick, the tick of gravity a flyer cancels
C.fly_flap_ticks = 12          -- one wingbeat's worth of the `swing` clip, at least
C.fly_flap_chance = 60         -- one tick in this many, a glider beats its wings to hold its height
C.fly_land_ticks = 200         -- how long a flyer spends coming down, or going up to roost, before it thinks better of it
-- Crows' flight plans (mobs.lua, "Crow navigation"). Heights are blocks
-- over the ground, times ticks, chances out of a hundred at each change of plan.
C.crow_cruise_min = 10         -- each bird's own cruising height, somewhere in here
C.crow_cruise_max = 18
C.crow_transit_min = 300       -- a straight leg: fifteen seconds to forty-five
C.crow_transit_max = 900
C.crow_circle_min = 6          -- a wheel's radius
C.crow_circle_max = 12
C.crow_circle_ticks_min = 200
C.crow_circle_ticks_max = 600
C.crow_tree_chance = 20        -- into a tree, by day
C.crow_tree_chance_night = 55  -- and after dark
C.crow_circle_chance = 30      -- of the rest: a circle
C.crow_ground_chance = 6       -- and down to the ground: rare
C.crow_tree_reach = 24         -- blocks around it a crow looks for a tree
C.crow_flock_tree_reach = 4    -- and a follower, around its leader's branch
C.crow_tree_tries = 6          -- columns looked at, one engine call each
C.crow_treed_min = 400         -- sitting in a tree: twenty seconds to two minutes
C.crow_treed_max = 2400
C.crow_leave = 112             -- flown this far past every player, it leaves the world
C.roost_reach = 8              -- blocks up a bat looks for a ceiling to hang from
C.roost_hang = 0.1             -- blocks a roosting bat's origin sits inside the ceiling, so its hanging feet meet it

-- The world's blocks, by name. Every id is looked up with pcall at load, so
-- a world without these still loads this mod; it just has no lava.
--
-- Standing IN one of these burns. `damage`/`ticks` are the contact hit and
-- `after` is how long the burning status lasts once out of it.
C.contact_fire = {
    ["tiamat_default_world:magma"] = { damage = C.lava_damage, ticks = C.lava_ticks, after = C.burn_after_lava },
    ["tiamat_default_life:campfire"] = { damage = C.campfire_damage, ticks = C.campfire_ticks, after = C.burn_after_campfire },
}
-- Heat sources, for temperature: strength 0..1 scales `temp_source_*`.
C.heat_sources = {
    ["tiamat_default_life:campfire"] = 1.0,
    ["tiamat_default_world:magma"] = 1.0,
    ["tiamat_default_world:magma_crust"] = 0.5,
    ["tiamat_default_world:lantern_stone"] = 0.6,
}
C.cold_sources = {
    ["tiamat_default_world:dream_stone"] = 0.8,
    ["tiamat_default_world:snow"] = 0.5,
    ["tiamat_default_world:permafrost"] = 0.3,
}
-- The world's biomes, by the ids Tiamat Default World's `biome_under`
-- answers. A creature names the ones it lives in (creatures.lua,
-- `spawn.biomes`); these are the lists more than one kind shares.
--
-- How often a kind turns up in a biome, as the weight it is drawn with at a
-- spawn spot there, against every other kind that lives there. A kind's
-- `spawn.biomes` names its biomes with one of these (creatures.lua), so
-- rarity is one decision per biome rather than a number to balance by hand.
C.common = 10
C.uncommon = 5
C.scarce = 2
C.rare = 1

-- Every surface biome that is dry land: what `spawn.land` means, for the
-- creatures that live anywhere on land (crows now, night monsters later).
C.land_biomes = {
    "temperate_woodlands", "rolling_grasslands", "alpine_highlands", "frozen_wastes", "coastal_cliffs",
    "sandy_shores", "dunes", "flower_forest", "heather_moor", "river_valleys", "jungle", "arid_mesa",
    "badlands", "taiga", "icefall", "silverwood", "salt_pan", "volcanic_foothills", "obsidian_barrens",
    "geyser_basin", "cinder_coast", "frostpine_coast", "rime_tundra", "rime_wall", "mangrove_coast",
    "savanna", "karst_towers", "peat_fen", "redwood_stands",
}
-- (Not land: deep_ocean, coral_fringed_shallows, kelp_forest, abyssal_trench, pack_ice.)
-- The ordinary caves, dark and lit: where bats live. The deep and magical
-- ones are for what comes later.
C.cave_biomes = {
    "mossy_limestone", "crystal_seam", "underground_river", "fungal_grove_chambers",
    "mineral_vein_tunnels", "stalactite_forests", "stone_labyrinth", "echoing_black_marble",
    "shadow_pool_chambers", "blind_fish_grottoes", "whispering_crevasse", "phosphorescent_fungi_pockets",
}

-- What a crow will perch on: the top of a tree, leaves, needles or a log.
C.perches = {}
for _, tree in ipairs({ "oak", "birch", "apple", "cherry", "acacia", "willow", "mangrove", "kapok", "ironwood" }) do
    C.perches[#C.perches + 1] = "tiamat_default_world:" .. tree .. "_leaves"
    C.perches[#C.perches + 1] = "tiamat_default_world:" .. tree .. "_log"
end
for _, tree in ipairs({ "fir", "redwood", "juniper" }) do
    C.perches[#C.perches + 1] = "tiamat_default_world:" .. tree .. "_needles"
    C.perches[#C.perches + 1] = "tiamat_default_world:" .. tree .. "_log"
end
C.perches[#C.perches + 1] = "tiamat_default_world:dead_log"
-- Ground cover a body walks through. Treated as clear when looking for
-- somewhere a creature can stand, so a meadow of tufts is not a wall.
C.passable_cover = {
    "tiamat_default_world:fern",
    "tiamat_default_world:tall_grass",
    "tiamat_default_world:ladys_mantle",
    "tiamat_default_world:ladys_mantle_bloom",
}
-- Blocks that irradiate whoever stands near them. None in the default world
-- yet; the mechanism is here for the one that will.
C.radiation_blocks = {}
C.radiation_ticks = 20 * 15

-- What a held thing does to whoever is hit with it. A bare hand is 1.
C.weapons = {
    ["core_gear:sword"] = 6,
}
C.fist_damage = 1

-- The ring a position is in, by its id, or nil beyond the rim.
function C.ring_at(x, z)
    local t = math.sqrt(x * x + z * z) / C.world_radius
    for _, ring in ipairs(C.rings) do
        if t >= ring.t[1] and t < ring.t[2] then return ring.id, t end
    end
    return nil, t
end

-- The world's climate at a position, as an ambient shift: 0 on the spawn
-- plain, warm toward the Glass Waste, cold toward the Crown and the Hem.
function C.climate_at(x, z)
    if not C.climate then return 0 end
    local t = math.sqrt(x * x + z * z) / C.world_radius
    if t > 1 then t = 1 end
    local T = 4 * t * (1 - t)
    return (T - C.climate_comfort) * C.climate_scale
end

-- A test harness may set `tdl_overrides` before the mod loads; a real
-- server never does.
for key, value in pairs(tdl_overrides or {}) do
    C[key] = value
end

-- Digging one of these also yields food: berries from the world's brambles.
C.forage = {
    ["tiamat_default_world:bramble"] = { item = "berries", count = 1 },
}

return C
