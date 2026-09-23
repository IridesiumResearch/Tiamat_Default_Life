-- SPDX-License-Identifier: GPL-3.0-only
--
-- The mob system: what lives in the world, where it appears, how it moves,
-- what it does to you and what it leaves behind.
--
-- A mob is an engine entity — position, collider, health, a model — plus a
-- state record kept here, keyed on the entity id. The engine persists the
-- entity with its chunk; the record is rebuilt when the mob is next seen
-- (`adopt`), so a cow that was there when the world closed is a cow when it
-- opens. Its KIND is read back off the entity: the model name for a kind
-- with a model of its own, and the nametag for one still drawn as the
-- engine's white humanoid.
--
--   tdl.register_mob(def)          a kind; see creatures.lua for the fields
--   tdl.spawn_mob(kind, pos, n)    puts some in the world now
--   tdl.hurt_mob(id, amount, by)   damage, and death, drops and fleeing
--   tdl.mobs_near(pos, radius)     ids of ours, nearest first
--   tdl.set_alight(target, ticks)  a player (UUID) or one of ours (id) burns
--
-- Everything that moves goes through the engine: `game.steer_entity` walks a
-- body toward a point and decides the jumping, a kind's own pace is `speed`
-- on the entity, and a flyer has its velocity set every tick. The one
-- teleport is a bat's last few inches onto its roost: it hangs by its feet
-- from the underside of a block, which puts its body's box a sliver INTO the
-- ceiling, and a body cannot fly into a block. The engine leaves a body that
-- starts a tick inside geometry where it is, and lets it move out.

local C = tdl.config
local U = tdl.util
local I = tdl.items

local M = { kinds = {}, order = {}, live = {} }
tdl.mobs = M

local ANIM_IDLE, ANIM_WALK, ANIM_RUN, ANIM_SWING = 0, 1, 2, 3
local ANIM_SNEAK = 5    -- the engine's sixth tag; a grazer's head-down clip rides on it
local PERCEIVE_EVERY = 10
local FIRE_EVERY = 5      -- ticks between looks at what a body stands in
local BURN_PERIOD = 10    -- burning after the fire: a point this often, as a player's
local now = 0

-- Randomness --------------------------------------------------------------------
--
-- A xorshift over Lua's own 64-bit integers, which wrap: the same world
-- ticked the same way rolls the same numbers on every machine (charter
-- rule 4), and nothing here calls the platform's `math.random`.
local seed = 0x2545F4914F6CDD1D

local function rand()
    seed = seed ~ (seed << 13)
    seed = seed ~ (seed >> 7)
    seed = seed ~ (seed << 17)
    return seed
end

--- An integer in 0..n-1.
local function below(n)
    return (rand() >> 1) % n
end

--- An integer in lo..hi.
local function between(lo, hi)
    return lo + below(hi - lo + 1)
end

-- Kinds ------------------------------------------------------------------------------

function tdl.register_mob(def)
    assert(def.id, "a mob needs an id")
    def.qualified = game.mod_id .. ":" .. def.id
    def.drops = def.drops or {}
    def.spawn = def.spawn or {}
    def.ground = U.materials(def.spawn.ground or {})
    -- A body of its own, wearing its skin. Behind a pcall, so a model the
    -- engine refuses is a log line here and a stand-in body, not a mod that
    -- fails to load.
    def.has_model = false
    if def.model and game.register_model then
        local ok, why = pcall(game.register_model, { id = def.id, file = def.model, texture = def.texture })
        def.has_model = ok
        if not ok then
            game.log("tiamat_default_life: " .. def.id .. " keeps its stand-in body: " .. tostring(why))
        end
    end
    M.kinds[def.id] = def
    M.order[#M.order + 1] = def.id
    return def
end

--- The kind of an entity of ours, or nil for a dropped stack.
local function kind_of(entity)
    if entity.item then return nil end
    if entity.model and entity.model ~= "engine:humanoid" then
        local short = string.match(entity.model, "^" .. game.mod_id .. ":(.+)$")
        if short and M.kinds[short] then return M.kinds[short] end
    end
    if entity.nametag then
        local short = string.lower(entity.nametag)
        if M.kinds[short] then return M.kinds[short] end
    end
    return nil
end

--- The state record for one of ours, made on first sight.
local function adopt(id, entity)
    local kind = kind_of(entity)
    if kind == nil then return nil end
    local m = {
        kind = kind,
        state = "idle",
        timer = between(10, 40),
        home = { x = entity.pos.x, y = entity.pos.y, z = entity.pos.z },
        target = nil,
        threat = nil,           -- a player UUID, while fleeing or hunting
        bite_cd = 0,
        hurt_cd = 0,
        flock = nil,            -- the leader's id, for a flocking kind
        offset = nil,
        voice = between(100, 600),
        perceive_at = (id % PERCEIVE_EVERY),
        seen = nil,             -- { uuid, pos, d2 } of the nearest player
        height = between(C.crow_cruise_min, C.crow_cruise_max),   -- a navigator's share of the sky
    }
    M.live[id] = m
    return m
end

--- Ids of our mobs near a position, nearest first.
function tdl.mobs_near(pos, radius)
    local out = {}
    for _, id in ipairs(game.entities_in_radius(pos, radius, game.mod_id)) do
        local entity = game.entity(id)
        if entity and not entity.item then out[#out + 1] = id end
    end
    return out
end

-- Spawning ------------------------------------------------------------------------------

--- Puts `count` of a kind at a position. Returns the ids.
function tdl.spawn_mob(kind_id, pos, count)
    local kind = M.kinds[kind_id]
    if kind == nil then return {} end
    local ids = {}
    local leader = nil
    for i = 1, count or 1 do
        local at = { x = pos.x + (i - 1) % 3 - 1, y = pos.y, z = pos.z + (i - 1) // 3 }
        local spec = {
            pos = at,
            health = kind.health,
            collider = kind.collider,
        }
        -- Its own body if the engine took one; else the stand-in, named.
        if kind.has_model or not C.placeholder_models then
            spec.model = kind.qualified
        else
            spec.model = "engine:humanoid"
            spec.nametag = kind.name
        end
        local id = game.spawn_entity(spec)
        if id then
            ids[#ids + 1] = id
            local entity = game.entity(id)
            local m = entity and adopt(id, entity)
            if m and kind.flock then
                leader = leader or id
                m.flock = leader
                m.offset = { x = between(-3, 3), y = between(0, 2), z = between(-3, 3) }
            end
            game.set_entity(id, { yaw = game.heading(between(-10, 10), between(-10, 10)) })
        end
    end
    return ids
end

local PASSABLE = U.materials((function()
    local set = {}
    for _, id in ipairs(C.passable_cover) do set[id] = true end
    return set
end)())

--- Standing room at (x, z) near height y: the first solid block scanning
--- down from above, with two clear blocks over it, where ground cover a
--- body walks through counts as clear and water does not. Returns the feet
--- position and the ground material, or nil.
local function ground_at(x, z, y)
    local clear = 0
    for yy = y + 10, y - 20, -1 do
        local block = game.get_block{ x = x, y = yy, z = z }
        if block == nil then return nil end
        if block.occupancy == 0 or PASSABLE[block.material] then
            clear = clear + 1
        else
            if clear >= 2 then
                local feet = { x = x, y = yy + 1, z = z }
                if game.get_fluid(feet).volume > 0 then return nil end
                return { x = x + 0.5, y = yy + 1, z = z + 0.5 }, block.material
            end
            clear = 0
        end
    end
    return nil
end

--- Somewhere to hang from: the nearest solid block above a point, within a
--- few blocks, or nil. Returns the middle of that block's underside.
local function ceiling_above(pos)
    local x, z = math.floor(pos.x), math.floor(pos.z)
    local y = math.floor(pos.y)
    for yy = y + 1, y + C.roost_reach do
        local block = game.get_block{ x = x, y = yy, z = z }
        if block == nil then return nil end
        if block.occupancy ~= 0 and not PASSABLE[block.material] then
            return { x = x + 0.5, y = yy, z = z + 0.5 }
        end
    end
    return nil
end

local function is_night()
    local t = game.time_of_day()
    return t < C.night_before or t > C.night_after
end

--- Whether a kind may appear at a spot right now.
local function may_spawn(kind, feet, material)
    local s = kind.spawn
    if next(kind.ground) ~= nil and not kind.ground[material] then return false end
    -- The world's rings, by radius: a creature of the temperate ring does
    -- not appear on the Glass Waste, whatever is underfoot.
    if s.rings then
        local ring = C.ring_at(feet.x, feet.z)
        local allowed = false
        for _, id in ipairs(s.rings) do
            if id == ring then allowed = true end
        end
        if not allowed then return false end
    end
    if s.time == "day" and is_night() then return false end
    if s.time == "night" and not is_night() then return false end
    local light = game.get_light{ x = math.floor(feet.x), y = math.floor(feet.y), z = math.floor(feet.z) }
    if s.sun_min and light.sun < s.sun_min then return false end
    if s.sun_max and light.sun > s.sun_max then return false end
    return true
end

--- One spawning pass around one player: pick a kind by weight, find ground
--- at a random distance, check the rules and the caps, and place a group.
local function try_spawn_near(v)
    local pos = v.pos
    if pos == nil then return end

    -- What is already about, by kind.
    local counts, total = {}, 0
    for _, id in ipairs(tdl.mobs_near(pos, C.mob_count_radius)) do
        local m = M.live[id]
        local kind = m and m.kind or (function()
            local e = game.entity(id)
            return e and kind_of(e)
        end)()
        if kind then
            counts[kind.id] = (counts[kind.id] or 0) + 1
            total = total + 1
        end
    end
    if total >= C.mob_cap_total then return end

    -- A kind by weight, among those under their cap.
    local weight_sum = 0
    for _, kid in ipairs(M.order) do
        local kind = M.kinds[kid]
        if (counts[kid] or 0) < (kind.spawn.cap or 4) then
            weight_sum = weight_sum + (kind.spawn.weight or 1)
        end
    end
    if weight_sum == 0 then return end
    local pick = below(weight_sum)
    local chosen
    for _, kid in ipairs(M.order) do
        local kind = M.kinds[kid]
        if (counts[kid] or 0) < (kind.spawn.cap or 4) then
            pick = pick - (kind.spawn.weight or 1)
            if pick < 0 then chosen = kind break end
        end
    end
    if chosen == nil then return end

    for _ = 1, C.mob_spawn_tries do
        -- A kind may say how far off it appears: crows, far out, so they
        -- come in over the horizon rather than out of a field beside you.
        local range = chosen.spawn.distance
        local dist = range and between(range[1], range[2]) or between(C.mob_spawn_min, C.mob_spawn_max)
        local dx = between(-dist, dist)
        local dz = (below(2) == 0 and 1 or -1) * (dist - math.abs(dx))
        local x, z = math.floor(pos.x) + dx, math.floor(pos.z) + dz
        local feet, material = ground_at(x, z, math.floor(pos.y))
        if feet and may_spawn(chosen, feet, material) then
            local group = chosen.spawn.group or { 1, 1 }
            local n = between(group[1], group[2])
            n = math.min(n, (chosen.spawn.cap or 4) - (counts[chosen.id] or 0))
            if n > 0 then
                -- A navigator appears already in the air, flying across the
                -- country the player is in: toward them, a little to one side.
                local at = feet
                if chosen.navigates then at = { x = feet.x, y = feet.y + C.crow_cruise_min, z = feet.z } end
                local ids = tdl.spawn_mob(chosen.id, at, n)
                local m = chosen.navigates and ids[1] and M.live[ids[1]]
                if m then
                    local hx = pos.x - feet.x + between(-12, 12)
                    local hz = pos.z - feet.z + between(-12, 12)
                    local length = math.sqrt(hx * hx + hz * hz)
                    if length > 0.001 then
                        m.heading = { x = hx / length, z = hz / length }
                        m.state, m.timer = "transit", C.crow_transit_max
                    end
                end
                if #ids > 0 then
                    game.log(string.format("tiamat_default_life: %d %s appeared at %d, %d, %d",
                        #ids, chosen.name, x, math.floor(feet.y), z))
                end
            end
            return
        end
    end
end

-- Damage and death ---------------------------------------------------------------------------

--- Hurts one of ours. `by` is the UUID of whoever did it, or nil.
-- Hearts over a hurt mob --------------------------------------------------------------
--
-- `game.show_over` hangs a row of pictures over an entity and follows it, so
-- the hearts are the HUD's own heart, one icon each, shown to the player who
-- struck the blow and nobody else. Latest state per entity: the next blow
-- replaces the row rather than stacking one on it.

local function show_hearts(id, kind, after, viewer)
    if not C.mob_hearts or viewer == nil or I.icons.heart_full == nil then return end
    -- Two points a heart, and never more than ten hearts: a bear's thirty
    -- points are ten hearts of three.
    local per = math.max(2, (kind.health + 9) // 10)
    game.show_over(id, {
        picture = I.icons.heart_full,
        count = (after + per - 1) // per,
        seconds = C.mob_hearts_seconds,
        size = C.mob_heart_size,
        player = viewer,
    })
end

function tdl.hurt_mob(id, amount, by)
    local entity = game.entity(id)
    if entity == nil or entity.health == nil then return false end
    local m = M.live[id] or adopt(id, entity)
    if m == nil then return false end
    if m.hurt_cd > 0 then return false end
    m.hurt_cd = 10

    local left = entity.health - U.round(amount)
    game.cue{ cue = "hurt", pos = entity.pos, radius = 16, gain = 0.6 }
    show_hearts(id, m.kind, math.max(left, 0), by)
    if left <= 0 then
        -- What it leaves behind, then gone.
        -- Burned to death, its meat comes out cooked.
        local burned = (m.burning or 0) > 0 or m.in_fire ~= nil
        for _, drop in ipairs(m.kind.drops) do
            local n = between(drop[2], drop[3] or drop[2])
            local item = burned and C.cooked_by_fire[drop[1]] or drop[1]
            if n > 0 then
                tdl.drop({ x = entity.pos.x, y = entity.pos.y + 0.5, z = entity.pos.z },
                    { material = I.defs[game.mod_id .. ":" .. item].material, units = n * 27 },
                    { velocity = { x = 0, y = 0.3, z = 0 } })
            end
        end
        if m.kind.sound_death then
            game.cue{ cue = m.kind.sound_death, pos = entity.pos, radius = 24 }
        end
        game.despawn_entity(id)
        M.live[id] = nil
        return true
    end
    game.set_entity(id, { health = left })

    -- Knocked back from whoever hit it, and a reaction: the timid run,
    -- the fierce turn on you.
    if by then
        local attacker = U.body(by)
        if attacker then
            local dx, dz = entity.pos.x - attacker.pos.x, entity.pos.z - attacker.pos.z
            local length = math.sqrt(dx * dx + dz * dz)
            if length > 0.001 then
                game.set_entity(id, { velocity = {
                    x = dx / length * C.knockback, y = C.knockback_up, z = dz / length * C.knockback } })
            end
        end
        if m.kind.hostile or m.kind.provoked then
            m.state, m.threat, m.timer = "hunt", by, C.mob_hunt_ticks
            m.angry = true
        else
            m.state, m.threat, m.timer = "flee", by, C.mob_flee_ticks
        end
    end
    return true
end

tdl.on_punch(function(event)
    if event.owner ~= nil then return end
    local entity = game.entity(event.target)
    if entity == nil or entity.source ~= game.mod_id or entity.item then return end
    local damage = C.fist_damage
    local held = game.held(event.attacker)
    if held and I.weapons[held.material] then damage = I.weapons[held.material] end
    tdl.hurt_mob(event.target, damage, event.attacker)
end)

-- Behaviour ------------------------------------------------------------------------------------

--- The nearest player within a kind's sight, refreshed every tenth tick.
local function perceive(m, entity)
    local best, best_d2, best_pos = nil, math.huge, nil
    for _, pid in ipairs(game.entities_in_radius(entity.pos, m.kind.sight or 12, "engine:player")) do
        local p = game.entity(pid)
        if p and p.owner and not ((m.kind.hostile or m.kind.provoked) and tdl.is_invulnerable(p.owner)) then
            local d2 = U.dist2(p.pos, entity.pos)
            if d2 < best_d2 then best, best_d2, best_pos = p.owner, d2, p.pos end
        end
    end
    if best then
        m.seen = { uuid = best, pos = best_pos, d2 = best_d2 }
    else
        m.seen = nil
    end
end

--- Whether a hostile kind is in the mood: bats in the dark, crows at night.
local function hunts_now(kind, entity)
    local h = kind.hostile
    if not h then return false end
    if h.when == "always" then return true end
    if h.when == "night" then return is_night() end
    if h.when == "dark" then
        if is_night() then return true end
        local at = U.block_at(entity.pos, 1)
        local light = game.get_light(at)
        return light.sun <= (h.sun_max or 3)
    end
    return false
end

--- A wander point around home, on the ground or in the air. A flyer that
--- has landed goes a few steps from where it stands, not across its range.
local function pick_wander(m, entity)
    local kind = m.kind
    if m.landed then
        m.target = { x = entity.pos.x + between(-3, 3), y = entity.pos.y, z = entity.pos.z + between(-3, 3) }
        return
    end
    local r = kind.wander_radius or 8
    local x = m.home.x + between(-r, r)
    local z = m.home.z + between(-r, r)
    local y = entity.pos.y
    if kind.flyer then
        y = m.home.y + between(kind.fly_low or 3, kind.fly_high or 9)
    end
    m.target = { x = x, y = y, z = z }
end

--- Walks a walker toward a point through the engine's steering, facing where
--- it goes and animating from what the body did last tick. Returns false once
--- it has arrived, or has given up on getting there.
---
--- How fast is the ENTITY's, not the drive's: `speed` is a multiple of the
--- ordinary pace, kept with the entity, so a kind that names its speeds in
--- blocks a second gets them by scaling the gait it is using. The engine
--- steers and decides the jumping: it walks a one-cell lip and jumps only
--- what the step cannot take.
local function walk_to(id, m, entity, target, gait)
    local kind = m.kind
    local want = gait == "sprint" and kind.run_speed or kind.walk_speed
    local spec = {}
    if want then
        local scale = want / (gait == "sprint" and C.player_sprint or C.player_walk)
        if m.speed ~= scale then
            m.speed, spec.speed = scale, scale
        end
    end
    local going = game.steer_entity(id, target, gait)

    -- Given up: a body that has not moved for a while is against something the
    -- engine cannot jump, and standing there is worse than going elsewhere.
    local speed2 = entity.velocity.x * entity.velocity.x + entity.velocity.z * entity.velocity.z
    if speed2 >= C.mob_moving_speed2 or not entity.on_ground then
        m.stuck = 0
    else
        m.stuck = (m.stuck or 0) + 1
        if m.stuck >= C.mob_stuck_ticks then
            m.stuck = 0
            return false
        end
    end

    -- A kind that `hangs` has its roost as its idle clip, so on the ground it
    -- rests on its eating clip instead.
    local anim = kind.hangs and ANIM_SNEAK or ANIM_IDLE
    if speed2 >= 0.0025 then anim = gait == "sprint" and ANIM_RUN or ANIM_WALK end
    spec.anim = anim
    spec.yaw = game.heading(target.x - entity.pos.x, target.z - entity.pos.z)
    game.set_entity(id, spec)
    return going ~= false
end

--- Which wing clip a flyer plays this tick: `swing` is the wingbeat and `run`
--- the glide with its wings held out. It beats them to climb, to hurry and to
--- lift off, for at least one beat at a time, and now and then in a long
--- glide to hold its height; the rest of the time it soars. A kind that
--- `flutters` never glides: `run` is its flight, and `swing` its bite.
local function wings(m, beat)
    if m.kind.flutters then
        if (m.swing or 0) > 0 then
            m.swing = m.swing - 1
            return ANIM_SWING
        end
        return ANIM_RUN
    end
    if beat then
        m.flap = math.max(m.flap or 0, C.fly_flap_ticks)
    elseif (m.flap or 0) <= 0 and below(C.fly_flap_chance) == 0 then
        m.flap = C.fly_flap_ticks
    end
    if (m.flap or 0) > 0 then
        m.flap = m.flap - 1
        return ANIM_SWING
    end
    return ANIM_RUN
end

--- Flies a flyer toward a point: velocity set every tick, lift added to
--- cancel the tick of gravity the physics is about to apply, and a rise
--- when the way ahead is solid.
local function fly_to(id, m, entity, target, speed, fast)
    local dx, dy, dz = target.x - entity.pos.x, target.y - entity.pos.y, target.z - entity.pos.z
    local flat = math.sqrt(dx * dx + dz * dz)
    local vx, vz = 0, 0
    if flat > 0.01 then vx, vz = dx / flat * speed, dz / flat * speed end
    local vy = U.clamp(dy * 0.15, -speed, speed)
    -- Something in the way at head height: go over it.
    local ahead = { x = math.floor(entity.pos.x + (flat > 0.01 and dx / flat or 0) * 1.5),
                    y = math.floor(entity.pos.y + 0.5), z = math.floor(entity.pos.z + (flat > 0.01 and dz / flat or 0) * 1.5) }
    local block = game.get_block(ahead)
    if block and block.occupancy ~= 0 then vy = speed end
    if entity.on_ground then vy = speed end
    game.set_entity(id, {
        velocity = { x = vx, y = vy + C.fly_lift, z = vz },
        yaw = game.heading(dx, dz),
        anim = wings(m, fast or vy > speed * 0.3),
    })
    return flat > 1.0 or math.abs(dy) > 1.5
end

--- Brings a flyer down onto a spot: gliding in with only half the lift, so
--- gravity does the descending, and a few wingbeats to brake over the last
--- two blocks.
local function glide_down(id, m, entity, target, speed)
    local dx, dy, dz = target.x - entity.pos.x, target.y - entity.pos.y, target.z - entity.pos.z
    local flat = math.sqrt(dx * dx + dz * dz)
    local vx, vz = 0, 0
    local along = math.min(speed * 0.6, flat * 0.2)
    if flat > 0.01 then vx, vz = dx / flat * along, dz / flat * along end
    game.set_entity(id, {
        velocity = { x = vx, y = U.clamp(dy * 0.15, -speed, 0) + C.fly_lift * 0.5, z = vz },
        yaw = flat > 0.3 and game.heading(dx, dz) or nil,
        anim = wings(m, dy > -2),
    })
end

--- Lifts a landed flyer off: it stops walking and the next flight's first
--- tick, finding it on the ground, climbs.
local function take_off(id, m)
    m.landed = false
    m.speed = nil
    game.set_entity(id, { drive = { walk = { x = 0, z = 0 } } })
end

local function move_to(id, m, entity, target, fast)
    local kind = m.kind
    if kind.flyer and not m.landed then
        return fly_to(id, m, entity, target, fast and (kind.speed_fast or 0.5) or (kind.speed or 0.3), fast)
    end
    return walk_to(id, m, entity, target, fast and "sprint" or "walk")
end

--- Stands still, on the ground. A flyer in the air has nothing to stand on
--- and is left to its last velocity.
local function stand(id, m)
    if not m.kind.flyer or m.landed then
        local anim = ((m.grazing and m.state == "idle") or m.kind.hangs) and ANIM_SNEAK or ANIM_IDLE
        -- A blow just struck: its swing clip, for as long as the swing lasts.
        if (m.swing or 0) > 0 then
            m.swing = m.swing - 1
            anim = ANIM_SWING
        end
        game.set_entity(id, { drive = { walk = { x = 0, z = 0 } }, anim = anim })
    end
end

--- Fire: what the body stands in, looked at every few ticks. In it, the
--- block's own hits and the burning it leaves; out of it, a point every
--- `BURN_PERIOD` ticks until the burning is over; in water, none of it. A
--- creature that catches fire panics, unless it is busy hunting. Returns
--- false if the fire killed it.
local function tick_fire(id, m, entity, dt)
    if (entity.submerged or 0) > 0 then
        m.burning, m.in_fire, m.fire_acc = 0, nil, 0
        return true
    end
    if (now + m.perceive_at) % FIRE_EVERY == 0 then
        local feet = U.block_at(entity.pos)
        m.in_fire = U.material_in(I.contact_fire, feet)
            or U.material_in(I.contact_fire, { x = feet.x, y = feet.y - 1, z = feet.z })
    end
    local fire = m.in_fire
    local hit = 0
    if fire then
        if (m.burning or 0) <= 0 and m.state ~= "hunt" then m.state, m.target = "panic", nil end
        m.burning = math.max(m.burning or 0, fire.after)
        m.fire_acc = (m.fire_acc or 0) + dt
        if m.fire_acc >= fire.ticks then
            m.fire_acc = 0
            hit = fire.damage
        end
    elseif (m.burning or 0) > 0 then
        m.burning = m.burning - dt
        m.fire_acc = (m.fire_acc or 0) + dt
        if m.fire_acc >= BURN_PERIOD then
            m.fire_acc = 0
            hit = 1
        end
    else
        return true
    end
    m.flame_acc = (m.flame_acc or 0) + dt
    if m.flame_acc >= C.flame_every then
        m.flame_acc = 0
        U.flames(entity.pos, m.kind.collider.height / 3)
    end
    if hit > 0 then
        tdl.hurt_mob(id, hit, nil)
        if M.live[id] == nil then return false end
    end
    return true
end

--- Sets a player (a UUID) or one of our creatures (an entity id) on fire
--- for `ticks`, or longer if it is already burning longer. Answers whether
--- there was anyone to set alight.
function tdl.set_alight(target, ticks)
    if type(target) == "string" then
        local v = tdl.get(target)
        if v == nil or v.dead then return false end
        tdl.effects.apply(v, "burning", ticks)
        return true
    end
    local entity = math.type(target) == "integer" and game.entity(target)
    if not entity then return false end
    local m = M.live[target] or adopt(target, entity)
    if m == nil then return false end
    if (m.burning or 0) <= 0 and m.state ~= "hunt" then m.state, m.target = "panic", nil end
    m.burning = math.max(m.burning or 0, ticks)
    return true
end

--- Away from a threat: a point on the far side of the body from it.
local function away_from(entity, from, flyer)
    local dx, dz = entity.pos.x - from.x, entity.pos.z - from.z
    return { x = entity.pos.x + dx * 2, y = entity.pos.y + (flyer and 3 or 0), z = entity.pos.z + dz * 2 }
end

-- Crow navigation -----------------------------------------------------------------
--
-- A kind that `navigates` (the crow) has no home to wander round. Its leader
-- keeps a flight plan and the flock follows it:
--
--   transit   straight-ish across the country at its cruising height, from
--             one horizon to the other, drifting a little off its heading
--   circle    wheeling round a point for a while
--   to_tree   down onto the top of a tree it picked, and then
--   treed     sitting there until its time is up or somebody comes near
--   land      now and then, down to the ground to walk and peck (the states
--             a lander already has)
--
-- When a plan ends it picks the next, and a crow that has flown on past
-- every player leaves the world. Only the leader chooses; the flock copies
-- it, down to each bird finding its own branch in the same tree.

--- A flat direction as a unit vector; a zero one is east.
local function unit(dx, dz)
    local length = math.sqrt(dx * dx + dz * dz)
    if length < 0.001 then return 1, 0 end
    return dx / length, dz / length
end

--- Its cruising height: its own share of the sky over the ground under it,
--- the ground found once a second with the engine's column walk.
local function cruise_y(m, entity)
    if m.cruise_at == nil or now >= m.cruise_at then
        m.cruise_at = now + 20
        local top = game.surface_at{ x = math.floor(entity.pos.x), z = math.floor(entity.pos.z),
            from = math.floor(entity.pos.y) + 32, depth = 128 }
        if top then m.cruise = top.y + 1 + m.height end
    end
    return m.cruise or entity.pos.y
end

local function start_transit(m, hx, hz)
    if hx == nil then
        if m.heading then
            hx, hz = m.heading.x, m.heading.z
        else
            hx, hz = between(-10, 10), between(-10, 10)
        end
    end
    hx, hz = unit(hx, hz)
    m.heading = { x = hx, z = hz }
    m.state, m.target, m.timer = "transit", nil, between(C.crow_transit_min, C.crow_transit_max)
end

local function start_circle(m, entity)
    local hx, hz = unit(m.heading and m.heading.x or 1, m.heading and m.heading.z or 0)
    m.spin = below(2) == 0 and 1 or -1
    m.radius = between(C.crow_circle_min, C.crow_circle_max)
    -- The centre is off to one side, so it turns into the circle from the
    -- way it was going rather than doubling back.
    m.centre = { x = entity.pos.x - hz * m.spin * m.radius, z = entity.pos.z + hx * m.spin * m.radius }
    m.state, m.target, m.timer = "circle", nil, between(C.crow_circle_ticks_min, C.crow_circle_ticks_max)
end

--- The top of a tree within `reach` blocks of `near`: a few columns tried,
--- each one call. The spot to stand on, or nil.
local function find_tree(entity, near, reach)
    for _ = 1, C.crow_tree_tries do
        local x = math.floor(near.x) + between(-reach, reach)
        local z = math.floor(near.z) + between(-reach, reach)
        local top = game.surface_at{ x = x, z = z, from = math.floor(entity.pos.y) + 8, depth = 128 }
        if top and I.perches[top.material] then
            return { x = x + 0.5, y = top.y + 1, z = z + 0.5 }
        end
    end
    return nil
end

local function start_tree(m, entity, near, reach)
    local tree = find_tree(entity, near or entity.pos, reach or C.crow_tree_reach)
    if tree == nil then return false end
    m.state, m.target, m.timer = "to_tree", tree, C.fly_land_ticks * 2
    return true
end

--- The next plan, when one ends: on along its way most often; round in a
--- circle; into a tree, more often after dark; and now and then down to the
--- ground.
local function choose_plan(m, entity)
    if below(100) < (is_night() and C.crow_tree_chance_night or C.crow_tree_chance) and start_tree(m, entity) then
        return
    end
    local r = below(100)
    if r < C.crow_ground_chance then
        m.state, m.target, m.timer = "land", nil, C.fly_land_ticks
    elseif r < C.crow_ground_chance + C.crow_circle_chance then
        start_circle(m, entity)
    elseif m.heading then
        -- On, a little off its old heading.
        local turn = between(-3, 3) * 0.1
        start_transit(m, m.heading.x - m.heading.z * turn, m.heading.z + m.heading.x * turn)
    else
        start_transit(m)
    end
end

--- Whether no player is within `r` blocks of a position.
local function far_from_everyone(pos, r)
    local r2 = r * r
    for _, v in pairs(tdl.online()) do
        if v.pos and U.dist2(v.pos, pos) < r2 then return false end
    end
    return true
end

--- One tick of a navigating flyer's plan. Answers false for a state that is
--- not one of its plans, so the caller carries on with it.
local function navigate(id, m, entity)
    local speed = m.kind.speed or 0.3
    local state = m.state
    if state == "transit" then
        if m.timer <= 0 then
            choose_plan(m, entity)
            return true
        end
        local h = m.heading
        -- A little drift, now and then, so it is not a ruled line.
        if (now + m.perceive_at) % 40 == 0 then
            local d = between(-2, 2) * 0.04
            h.x, h.z = unit(h.x - h.z * d, h.z + h.x * d)
        end
        fly_to(id, m, entity, { x = entity.pos.x + h.x * 12, y = cruise_y(m, entity), z = entity.pos.z + h.z * 12 },
            speed, false)
        return true
    end
    if state == "circle" then
        if m.timer <= 0 then
            choose_plan(m, entity)
            return true
        end
        -- Aim a little ahead round the circle: out along the radius, then on
        -- along the tangent, so it closes on the circle and follows it.
        local ux, uz = unit(entity.pos.x - m.centre.x, entity.pos.z - m.centre.z)
        local tx, tz = -uz * m.spin, ux * m.spin
        m.heading = { x = tx, z = tz }
        local r = m.radius
        fly_to(id, m, entity, { x = m.centre.x + (ux + tx * 0.6) * r, y = cruise_y(m, entity),
                                z = m.centre.z + (uz + tz * 0.6) * r }, speed, false)
        return true
    end
    if state == "to_tree" then
        local t = m.target
        if entity.on_ground then
            m.treed = true
            m.state, m.timer = "treed", between(C.crow_treed_min, C.crow_treed_max)
            game.set_entity(id, { drive = { walk = { x = 0, z = 0 } }, anim = ANIM_IDLE })
            return true
        end
        if m.timer <= 0 then
            choose_plan(m, entity)
            return true
        end
        local dx, dz = t.x - entity.pos.x, t.z - entity.pos.z
        if dx * dx + dz * dz > 4 then
            fly_to(id, m, entity, { x = t.x, y = t.y + 3, z = t.z }, speed, false)
        else
            glide_down(id, m, entity, t, speed)
        end
        return true
    end
    if state == "treed" then
        if m.timer <= 0 then
            if m.stay then
                m.timer = between(60, 200)
            else
                -- Off again, on its way: the flight's first tick lifts it.
                m.treed = false
                start_transit(m)
                return true
            end
        end
        game.set_entity(id, { anim = ANIM_IDLE })
        return true
    end
    -- In the air with no plan (after a fright, a take-off, a reload): one.
    if not m.landed and (state == "idle" or state == "wander") then
        choose_plan(m, entity)
        return true
    end
    return false
end

local function step(id, dt)
    local entity = game.entity(id)
    if entity == nil or entity.item then return end
    local m = M.live[id] or adopt(id, entity)
    if m == nil then return end
    local kind = m.kind

    m.timer = m.timer - dt
    if m.hurt_cd > 0 then m.hurt_cd = m.hurt_cd - dt end
    if m.bite_cd > 0 then m.bite_cd = m.bite_cd - dt end
    if (now + m.perceive_at) % PERCEIVE_EVERY == 0 then perceive(m, entity) end
    if not tick_fire(id, m, entity, dt) then return end

    -- A voice now and then.
    m.voice = m.voice - dt
    if m.voice <= 0 then
        m.voice = between(kind.voice_min or 200, kind.voice_max or 900)
        if kind.sound then game.cue{ cue = kind.sound, pos = entity.pos, radius = 24, entity = id } end
    end

    -- Noticing: the fierce start hunting; the timid shy away from a player
    -- who comes close.
    if m.state ~= "flee" and m.state ~= "hunt" and m.seen then
        if kind.hostile and hunts_now(kind, entity) then
            m.state, m.threat, m.timer = "hunt", m.seen.uuid, C.mob_hunt_ticks
        elseif kind.shy and m.seen.d2 < U.square((m.treed or m.landed) and kind.wary or kind.shy) then
            m.state, m.threat, m.timer = "flee", m.seen.uuid, C.mob_flee_ticks // 2
        end
    end

    -- A bird on the ground, or a bat on its roost, that is frightened, angry
    -- or on fire takes to the air.
    if m.state == "flee" or m.state == "hunt" or m.state == "panic" then
        if m.landed then take_off(id, m) end
        m.roosting, m.treed = false, false
    end

    if m.state == "flee" then
        local from = U.body(m.threat)
        if from and m.timer > 0 then
            move_to(id, m, entity, away_from(entity, from.pos, kind.flyer), true)
        elseif kind.navigates then
            -- Frightened off, a crow goes on its way, away from whoever it was.
            m.threat = nil
            if from then
                start_transit(m, entity.pos.x - from.pos.x, entity.pos.z - from.pos.z)
            else
                start_transit(m)
            end
        else
            m.state, m.threat, m.timer = "idle", nil, between(20, 60)
            stand(id, m)
        end
        return
    end

    -- On fire: running anywhere, fast, until it goes out.
    if m.state == "panic" then
        if (m.burning or 0) <= 0 and m.in_fire == nil then
            m.state, m.target, m.timer = "idle", nil, between(20, 60)
            stand(id, m)
            return
        end
        if m.target == nil or not move_to(id, m, entity, m.target, true) then
            m.target = { x = entity.pos.x + between(-6, 6), y = entity.pos.y + (kind.flyer and 3 or 0),
                         z = entity.pos.z + between(-6, 6) }
        end
        return
    end

    if m.state == "hunt" then
        local prey = U.body(m.threat)
        local v = m.threat and tdl.get(m.threat)
        if prey and v and not v.dead and not tdl.is_invulnerable(m.threat) and m.timer > 0
            and (m.angry or hunts_now(kind, entity)) then
            -- Reach is measured to the body's middle, not its feet: a flyer
            -- hovers at chest height and would otherwise never be close.
            local middle = { x = prey.pos.x, y = prey.pos.y + 0.9, z = prey.pos.z }
            local d2 = U.dist2(middle, entity.pos)
            local bite = kind.bite
            if bite and d2 <= bite.range * bite.range then
                if m.bite_cd <= 0 then
                    m.bite_cd = bite.cooldown
                    local dx, dz = prey.pos.x - entity.pos.x, prey.pos.z - entity.pos.z
                    local length = math.sqrt(dx * dx + dz * dz)
                    local push = length > 0.001 and { x = dx / length * 0.4, y = 0.3, z = dz / length * 0.4 } or nil
                    tdl.damage(m.threat, bite.damage, "physical", { push = push, cause = bite.cause })
                    game.cue{ cue = "bite", pos = entity.pos, radius = 16 }
                    m.swing = C.mob_swing_ticks
                    -- Hit and run: a flyer wheels away after a bite.
                    if kind.flyer then
                        m.state, m.timer = "flee", 30
                        return
                    end
                end
                stand(id, m)
            else
                local at = { x = prey.pos.x, y = prey.pos.y + (kind.flyer and 1.2 or 0), z = prey.pos.z }
                move_to(id, m, entity, at, true)
            end
        else
            m.state, m.threat, m.timer = "idle", nil, between(20, 60)
            m.angry = false
            stand(id, m)
        end
        return
    end

    -- Flocking: a follower keeps its place beside the leader; a leader
    -- wanders like anybody else. A leader that is gone leaves the follower
    -- to lead itself. When the leader comes down the flock comes down too,
    -- each bird on the ground under itself, and they keep their own company
    -- there (`stay`: walking and eating, never flying off alone) until the
    -- leader lifts off again.
    m.stay = false
    if kind.flock and m.flock and m.flock ~= id then
        local leader = game.entity(m.flock)
        if leader and not leader.item then
            local lm = M.live[m.flock]
            if lm and lm.state == "hunt" and hunts_now(kind, entity) and m.seen then
                m.state, m.threat, m.timer = "hunt", lm.threat, C.mob_hunt_ticks
                return
            end
            if lm and (lm.treed or lm.state == "to_tree") then
                -- Into the same tree, each on a branch of its own; the ground
                -- under it if there is no branch to be had.
                m.stay = true
                if not m.treed and m.state ~= "to_tree" and not m.landed and m.state ~= "land"
                    and not start_tree(m, entity, lm.target or leader.pos, C.crow_flock_tree_reach) then
                    m.state, m.target, m.timer = "land", nil, C.fly_land_ticks
                end
            elseif lm and (lm.landed or lm.state == "land") then
                m.stay = true
                if not m.landed and m.state ~= "land" then
                    m.state, m.target, m.timer = "land", nil, C.fly_land_ticks
                end
            else
                if m.landed then take_off(id, m) end
                if m.treed then m.treed, m.state = false, "idle" end
                local at = { x = leader.pos.x + m.offset.x, y = leader.pos.y + m.offset.y, z = leader.pos.z + m.offset.z }
                if U.dist2(at, entity.pos) > 2 then
                    move_to(id, m, entity, at, false)
                else
                    stand(id, m)
                end
                return
            end
        else
            m.flock = nil
        end
    end

    if kind.navigates then
        -- Gone on past everyone: out of the world, rather than a crow at the
        -- edge of it for ever. Checked every couple of seconds, in the air.
        if (now + m.perceive_at) % 40 == 0 and not m.treed and not m.landed
            and far_from_everyone(entity.pos, C.crow_leave) then
            game.despawn_entity(id)
            M.live[id] = nil
            return
        end
        if navigate(id, m, entity) then return end
    end

    -- Going to roost: up under the ceiling it chose, and when it is there, its
    -- feet to the block and its body hanging below. It hangs, held against
    -- gravity, until its rest is over or somebody gives it cause.
    if m.state == "perch" then
        local c = m.target
        local under = { x = c.x, y = c.y - 0.5, z = c.z }
        local dx, dy, dz = under.x - entity.pos.x, under.y - entity.pos.y, under.z - entity.pos.z
        if m.timer <= 0 then
            m.state, m.timer = "wander", between(60, 200)
            pick_wander(m, entity)
        elseif dx * dx + dz * dz < 0.25 and math.abs(dy) < 0.6 then
            m.roosting = true
            m.state, m.timer = "roost", between(kind.roost_min or 400, kind.roost_max or 1600)
            game.set_entity(id, {
                pos = { x = c.x, y = c.y + C.roost_hang, z = c.z },
                velocity = { x = 0, y = C.fly_lift, z = 0 },
                anim = ANIM_IDLE,
            })
        else
            fly_to(id, m, entity, under, kind.speed or 0.3, false)
        end
        return
    end
    if m.state == "roost" then
        if m.timer <= 0 or not m.roosting then
            m.roosting = false
            m.state, m.timer = "wander", between(60, 200)
            pick_wander(m, entity)
            return
        end
        game.set_entity(id, { velocity = { x = 0, y = C.fly_lift, z = 0 }, anim = ANIM_IDLE })
        return
    end

    -- Coming down: find the ground under it, glide onto it, and it has landed.
    -- Water or nothing below, or too long about it, and it flies on instead.
    if m.state == "land" then
        if entity.on_ground then
            m.landed, m.target = true, nil
            m.state = "idle"
            m.timer = between(kind.pause_min or 40, kind.pause_max or 160)
            m.grazing = kind.grazes and below(2) == 0
            stand(id, m)
            return
        end
        if m.target == nil then
            m.target = ground_at(math.floor(entity.pos.x), math.floor(entity.pos.z), math.floor(entity.pos.y))
        end
        if m.target == nil or m.timer <= 0 then
            m.state, m.timer = "wander", between(60, 200)
            pick_wander(m, entity)
            return
        end
        glide_down(id, m, entity, m.target, kind.speed or 0.3)
        return
    end

    if m.state == "idle" then
        if m.timer <= 0 then
            -- On the ground, half its pauses end in the air again, unless its
            -- flock is still down; the rest in a few steps on foot.
            if m.landed and not m.stay and below(2) == 0 then take_off(id, m) end
            m.state = "wander"
            m.timer = m.landed and between(40, 100) or between(60, 200)
            pick_wander(m, entity)
        elseif kind.flyer and not m.landed then
            -- A flyer never idles on the ground: it circles.
            if m.target == nil then pick_wander(m, entity) end
            move_to(id, m, entity, m.target, false)
        else
            stand(id, m)
        end
        return
    end

    if m.state == "wander" then
        local going = m.target and move_to(id, m, entity, m.target, false)
        if not going or m.timer <= 0 then
            m.state = "idle"
            m.timer = between(kind.pause_min or 40, kind.pause_max or 160)
            -- A grazer spends about half its pauses with its head down.
            m.grazing = kind.grazes and below(2) == 0
            if kind.flyer and not m.landed then
                -- A bat with a ceiling over it roosts about two pauses in three;
                -- a bird that lands spends about half its pauses on the ground.
                local ceiling = kind.hangs and below(3) ~= 0 and ceiling_above(entity.pos)
                if ceiling then
                    m.state, m.target, m.timer = "perch", ceiling, C.fly_land_ticks
                elseif kind.lands and below(2) == 0 then
                    m.state, m.target, m.timer = "land", nil, C.fly_land_ticks
                else
                    pick_wander(m, entity)
                end
            end
        end
        return
    end
end

tdl.on_entity_step(step)

-- The tick: spawning, and forgetting what is far away ------------------------------------

local spawn_acc = 0

tdl.on_tick(function(dt)
    now = now + dt
    spawn_acc = spawn_acc + dt
    if spawn_acc < C.mob_spawn_every then return end
    spawn_acc = 0
    for _, v in pairs(tdl.online()) do
        try_spawn_near(v)
    end
    -- Records for mobs that are gone or frozen with their chunk.
    for id in pairs(M.live) do
        if game.entity(id) == nil then M.live[id] = nil end
    end
end)

-- Chat words, for testing ---------------------------------------------------------------------

if C.dev_commands then
    tdl.command("spawn", "admin", function(uuid, rest)
        local kind, n = string.match(rest, "^(%a+)%s*(%d*)$")
        local body = U.body(uuid)
        if kind == nil or body == nil or M.kinds[kind] == nil then
            tdl.say(uuid, "spawn <cow|sheep|pig|bear|crow|bat> [count]")
            return
        end
        local at = { x = body.pos.x + body.facing.x * 4, y = body.pos.y + (M.kinds[kind].flyer and 3 or 0),
                     z = body.pos.z + body.facing.z * 4 }
        local ids = tdl.spawn_mob(kind, at, tonumber(n) or 1)
        tdl.say(uuid, #ids .. " " .. kind .. (#ids == 1 and "" or "s") .. " spawned.")
    end)
    tdl.command("mobs", "admin", function(uuid)
        local body = U.body(uuid)
        if body == nil then return end
        local counts = {}
        for _, id in ipairs(tdl.mobs_near(body.pos, C.mob_count_radius)) do
            local m = M.live[id]
            local name = m and m.kind.id or "?"
            counts[name] = (counts[name] or 0) + 1
        end
        local parts = {}
        for name, n in pairs(counts) do parts[#parts + 1] = n .. " " .. name end
        table.sort(parts)
        tdl.say(uuid, #parts > 0 and table.concat(parts, ", ") or "nothing about")
    end)
    --- The nearest mob (of a kind, if one is named) as the server sees it:
    --- what it is doing, which clip it is told to play, and how fast it is
    --- going. For checking in play.
    local ANIM_NAMES = { [0] = "idle", "walk", "run", "swing", "swim", "sneak" }
    tdl.command("mob", "admin", function(uuid, rest)
        local body = U.body(uuid)
        local id
        for _, near in ipairs(body and tdl.mobs_near(body.pos, C.mob_count_radius) or {}) do
            local r = M.live[near]
            if rest == nil or rest == "" or (r and r.kind.id == rest) then id = near break end
        end
        local entity = id and game.entity(id)
        if entity == nil then
            tdl.say(uuid, "No mob near.")
            return
        end
        local m = M.live[id]
        local v = entity.velocity
        local speed = math.sqrt(v.x * v.x + v.z * v.z) * 20 / 3
        tdl.say(uuid, string.format("%s #%d: %s, clip %s, %.2f blocks/s%s",
            m and m.kind.id or "?", id, m and m.state or "?", ANIM_NAMES[entity.anim] or tostring(entity.anim),
            speed, entity.on_ground and "" or ", in the air"))
    end)
    --- Puts the nearest crow on a plan, to watch one without waiting for it.
    tdl.command("plan", "admin", function(uuid, rest)
        local body = U.body(uuid)
        local id, m
        for _, near in ipairs(body and tdl.mobs_near(body.pos, C.mob_count_radius) or {}) do
            local r = M.live[near]
            if r and r.kind.navigates then id, m = near, r break end
        end
        local entity = id and game.entity(id)
        if entity == nil then
            tdl.say(uuid, "No crow near.")
            return
        end
        if m.landed then take_off(id, m) end
        m.treed = false
        if rest == "transit" then
            start_transit(m)
        elseif rest == "circle" then
            start_circle(m, entity)
        elseif rest == "tree" then
            if not start_tree(m, entity) then
                tdl.say(uuid, "No tree near it.")
                return
            end
        elseif rest == "land" then
            m.state, m.target, m.timer = "land", nil, C.fly_land_ticks
        else
            tdl.say(uuid, "plan <transit|circle|tree|land>")
            return
        end
        tdl.say(uuid, "Crow #" .. id .. ": " .. m.state .. ".")
    end)
    tdl.command("ignite", "admin", function(uuid, rest)
        local body = U.body(uuid)
        local id = body and tdl.mobs_near(body.pos, C.mob_count_radius)[1]
        if id == nil then
            tdl.say(uuid, "No mob near.")
            return
        end
        tdl.set_alight(id, tonumber(rest) or 100)
        tdl.say(uuid, "Alight.")
    end)
    tdl.command("cull", "admin", function(uuid)
        local body = U.body(uuid)
        if body == nil then return end
        local n = 0
        for _, id in ipairs(tdl.mobs_near(body.pos, C.mob_count_radius)) do
            game.despawn_entity(id)
            M.live[id] = nil
            n = n + 1
        end
        tdl.say(uuid, n .. " gone.")
    end)
end

return M
