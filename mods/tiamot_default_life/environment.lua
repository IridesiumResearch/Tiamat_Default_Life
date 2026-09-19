-- SPDX-License-Identifier: GPL-3.0-only
--
-- What the world is doing to each body: is the head under water, are the
-- feet in lava, is there a fire nearby, is it night, did they just land hard.
-- Written into `v.env` for vitals.lua to act on, and nothing is acted on
-- here except falls, which are an event rather than a state.
--
-- Water and falls are the engine's own answers, read off the body every
-- tick: `submerged` is the share of the body in fluid, the number the physics
-- moved it by, and `fell` is the blocks it fell, on the tick it lands.
--
-- Cost, per player: one entity read a tick; a few block reads every
-- fourth tick; a 7x3x7 scan for heat and cold every tenth; the worn view
-- every fortieth. Staggered by tick so they do not all land together.

local C = tdl.config
local U = tdl.util
local I = tdl.items

local BLOCKS_EVERY = 4
local SOURCES_EVERY = 10
local WORN_EVERY = 40

local EYE = 1.62          -- blocks above the feet
local R = C.temp_source_radius

local now = 0

--- Whether a block holds one of the materials in `set`, returning the entry.
local function material_in(set, pos)
    local at = game.get_block(pos)
    if at == nil or at.occupancy == 0 then return nil end
    if at.cells then
        for _, material in ipairs(at.cells) do
            if set[material] then return set[material] end
        end
        return nil
    end
    return set[at.material]
end

--- How deep in fluid the body is, from the engine's own measure.
local function sample_fluid(v, body)
    local env = v.env
    local share = body.submerged or 0
    env.submerged = share >= C.submerged_head
    env.wet = share > 0
    env.swimming = share >= C.submerged_swimming
end

local function sample_blocks(v, body)
    local env = v.env
    local pos = body.pos
    local feet = U.block_at(pos)
    local head = U.block_at(pos, EYE)

    -- Fire: the block the feet are in, the one they stand on, the head.
    local below = { x = feet.x, y = feet.y - 1, z = feet.z }
    env.fire = material_in(I.contact_fire, feet) or material_in(I.contact_fire, below)
        or material_in(I.contact_fire, head)
end

local function sample_sources(v, body)
    local env = v.env
    local pos = body.pos
    local feet = U.block_at(pos)
    local head = U.block_at(pos, EYE)

    -- The world's climate first: where on the disc the body stands.
    local ambient = C.climate_at(pos.x, pos.z)
    env.ring = C.ring_at(pos.x, pos.z)

    -- Then the sky's share: caves are cool; nights are cold; midday is warm.
    local sun = game.get_light(head).sun
    if sun <= C.cave_sun_max then
        ambient = ambient + C.temp_cave
    else
        local time = game.time_of_day()
        local open = sun / 15
        if time < C.night_before or time > C.night_after then
            ambient = ambient + C.temp_night * open
        else
            local day = 1 - math.abs(time - 0.5) / (0.5 - C.night_before)
            ambient = ambient + C.temp_noon * U.clamp(day, 0, 1) * open
        end
    end
    if env.submerged then
        ambient = ambient + C.temp_water
    elseif env.wet then
        ambient = ambient + C.temp_wet
    end

    -- Heat and cold sources around the body, strongest wins on each side.
    local heat, cold = 0, 0
    local radiation = false
    for dy = -1, 1 do
        for dx = -R, R do
            for dz = -R, R do
                local at = { x = feet.x + dx, y = feet.y + dy, z = feet.z + dz }
                local block = game.get_block(at)
                if block and block.occupancy ~= 0 then
                    local material = block.material
                    local near = dx >= -1 and dx <= 1 and dz >= -1 and dz <= 1
                    local reach = near and C.temp_source_near or C.temp_source_far
                    local h = I.heat_sources[material]
                    if h and h * reach > heat then heat = h * reach end
                    local c = I.cold_sources[material]
                    if c and c * reach > cold then cold = c * reach end
                    if I.radiation_blocks[material] then radiation = true end
                end
            end
        end
    end
    env.heat, env.cold = heat, cold
    env.radiation = radiation
    env.ambient = U.clamp(ambient + heat - cold, -1, 1)
end

local function sample_worn(uuid, v)
    local warmth, armour = 0, 0
    for _, stack in ipairs(game.inventory(uuid, I.worn_view)) do
        local def = I.by_material[stack.material]
        if def and def.kind == "clothing" then
            warmth = warmth + def.warmth
            armour = armour + (def.armour or 0)
        end
    end
    v.warmth, v.armour = warmth, armour
end

--- Falls: the engine says how far, on the tick the body lands. It counts a
--- flight down to the ground as a fall too, so a landing only hurts if the
--- body was moving down fast the tick before; drifting down is flying. And
--- nothing hurts landing in water.
local function track_fall(uuid, v, body)
    local fall = body.fell or 0
    if fall > C.fall_safe_blocks and (v.last_vy or 0) <= -C.fall_min_speed and not v.env.wet then
        local damage = (fall - C.fall_safe_blocks) * C.fall_damage_per_block
        tdl.cue(uuid, "thud")
        tdl.damage(uuid, damage, "fall")
    end
    v.last_vy = body.velocity.y
end

tdl.on_tick(function(dt)
    now = now + dt
    local slot = 0
    for uuid, v in pairs(tdl.online()) do
        slot = slot + 1
        local body = U.body(uuid)
        if body then
            v.pos = body.pos
            v.env.on_ground = body.on_ground
            local vx, vz = body.velocity.x, body.velocity.z
            v.env.speed2 = vx * vx + vz * vz

            sample_fluid(v, body)
            if (now + slot) % BLOCKS_EVERY == 0 then sample_blocks(v, body) end
            if (now + slot) % SOURCES_EVERY == 0 then sample_sources(v, body) end
            if (now + slot) % WORN_EVERY == 0 then sample_worn(uuid, v) end
            if not v.dead then track_fall(uuid, v, body) end
        else
            v.env.speed2 = 0
        end
    end
end)

return {}
