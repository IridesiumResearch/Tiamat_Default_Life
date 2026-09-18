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
C.temp_uncomfortable = 0.55    -- "cold" / "hot": hunger burns faster, nothing else
C.temp_extreme = 0.90          -- "freezing" / "overheating": slow damage
C.temp_damage_ticks = 100      -- a point every five seconds at an extreme
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

-- The world's own climate. Tiamot Default World (the Spindle) makes its
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

-- Falls -------------------------------------------------------------------

C.fall_safe_blocks = 3.0       -- no damage up to this
C.fall_damage_per_block = 1.5  -- past that
C.fall_min_speed = 1.2         -- cells per tick downward at impact, or it was not a fall (flying lands slower)

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
C.rested_ticks = 20 * 60 * 5   -- five minutes of well-rested
C.well_fed_ticks = 20 * 60 * 3 -- three minutes after a proper meal

-- Explosions --------------------------------------------------------------

C.explosion_push = 2.5         -- cells per tick at the centre
C.explosion_push_up = 0.8

-- Mobs ---------------------------------------------------------------------

-- Until the engine draws a model a mod ships, every creature is the
-- engine's white humanoid with its kind as a nametag. Set false once
-- `register_model` exists and the creatures carry their own models.
C.placeholder_models = true
C.mob_spawn_every = 100        -- ticks between spawning passes, per player
C.mob_spawn_tries = 6          -- ground spots tried per pass
C.mob_spawn_min = 20           -- blocks from the player, at least
C.mob_spawn_max = 44           -- and at most
C.mob_count_radius = 64        -- how far around a player the caps count
C.mob_cap_total = 32           -- of everything, per player
C.mob_flee_ticks = 100         -- five seconds of running from a hit
C.mob_hunt_ticks = 400         -- twenty seconds of chasing before losing interest
C.fly_lift = 0.24              -- cells per tick, the tick of gravity a flyer cancels

-- The world's blocks, by name. Every id is looked up with pcall at load, so
-- a world without these still loads this mod; it just has no lava.
--
-- Standing IN one of these burns. `damage`/`ticks` are the contact hit and
-- `after` is how long the burning status lasts once out of it.
C.contact_fire = {
    ["tiamot_default_world:magma"] = { damage = C.lava_damage, ticks = C.lava_ticks, after = C.burn_after_lava },
    ["tiamot_default_life:campfire"] = { damage = C.campfire_damage, ticks = C.campfire_ticks, after = C.burn_after_campfire },
}
-- Heat sources, for temperature: strength 0..1 scales `temp_source_*`.
C.heat_sources = {
    ["tiamot_default_life:campfire"] = 1.0,
    ["tiamot_default_world:magma"] = 1.0,
    ["tiamot_default_world:magma_crust"] = 0.5,
    ["tiamot_default_world:lantern_stone"] = 0.6,
}
C.cold_sources = {
    ["tiamot_default_world:dream_stone"] = 0.8,
    ["tiamot_default_world:snow"] = 0.5,
    ["tiamot_default_world:permafrost"] = 0.3,
}
-- Ground cover a body walks through. Treated as clear when looking for
-- somewhere a creature can stand, so a meadow of tufts is not a wall.
C.passable_cover = {
    "tiamot_default_world:fern",
    "tiamot_default_world:tall_grass",
    "tiamot_default_world:ladys_mantle",
    "tiamot_default_world:ladys_mantle_bloom",
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
    ["tiamot_default_world:bramble"] = { item = "berries", count = 1 },
}

return C
