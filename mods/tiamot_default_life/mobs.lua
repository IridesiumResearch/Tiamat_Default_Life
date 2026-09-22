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
--
-- Everything that moves goes through the engine's physics: a walker's drive
-- is set toward a point and the body walks it, stepping up a cell on its
-- own; a flyer has its velocity set every tick. Nothing here teleports.

local C = tdl.config
local U = tdl.util
local I = tdl.items

local M = { kinds = {}, order = {}, live = {} }
tdl.mobs = M

local ANIM_IDLE, ANIM_WALK, ANIM_RUN, ANIM_SWING = 0, 1, 2, 3
local ANIM_SNEAK = 5    -- the engine's sixth tag; a grazer's head-down clip rides on it
local PERCEIVE_EVERY = 10
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
            game.log("tiamot_default_life: " .. def.id .. " keeps its stand-in body: " .. tostring(why))
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
        local dist = between(C.mob_spawn_min, C.mob_spawn_max)
        local dx = between(-dist, dist)
        local dz = (below(2) == 0 and 1 or -1) * (dist - math.abs(dx))
        local x, z = math.floor(pos.x) + dx, math.floor(pos.z) + dz
        local feet, material = ground_at(x, z, math.floor(pos.y))
        if feet and may_spawn(chosen, feet, material) then
            local group = chosen.spawn.group or { 1, 1 }
            local n = between(group[1], group[2])
            n = math.min(n, (chosen.spawn.cap or 4) - (counts[chosen.id] or 0))
            if n > 0 then
                local ids = tdl.spawn_mob(chosen.id, feet, n)
                if #ids > 0 then
                    game.log(string.format("tiamot_default_life: %d %s appeared at %d, %d, %d",
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
-- The engine can put no picture over an entity, but a particle with no spread,
-- no speed and no gravity stays exactly where it is put. So the row of hearts
-- is drawn in pixels, one particle each, for the player who struck the blow
-- and nobody else, turned square to them. Red is what
-- is left, a white flash is what that hit took, dark is what was gone before.

local HEART = { "XX.XX", "XXXXX", ".XXX.", "..X.." }

local function show_hearts(entity, kind, before, after, viewer)
    local body = viewer and U.body(viewer)
    if body == nil or not C.mob_hearts then return end
    local dx, dz = entity.pos.x - body.pos.x, entity.pos.z - body.pos.z
    local length = math.sqrt(dx * dx + dz * dz)
    if length < 0.001 then return end
    -- Across the viewer's line of sight: their right, as they face the mob.
    local rx, rz = -dz / length, dx / length
    local px = C.mob_heart_pixel
    -- Two points a heart, and never more than ten hearts: a bear's thirty
    -- points are ten hearts of three.
    local per = math.max(2, (kind.health + 9) // 10)
    local hearts = (kind.health + per - 1) // per
    local width = hearts * 6 - 1
    local top = entity.pos.y + (kind.collider and kind.collider.height or 3) / 3 + C.mob_hearts_above
    for h = 0, hearts - 1 do
        for row = 1, #HEART do
            local line = HEART[row]
            for col = 1, 5 do
                if string.sub(line, col, col) == "X" then
                    -- Which point of the mob's health this pixel stands for:
                    -- a heart's points run left to right across its columns.
                    local point = h * per + math.max(1, math.ceil(col * per / 5 - 0.01))
                    local colour, life
                    if point <= after then
                        colour, life = { r = 0.86, g = 0.1, b = 0.12 }, C.mob_hearts_seconds
                    elseif point <= before then
                        colour, life = { r = 1, g = 1, b = 1 }, C.mob_hearts_seconds / 3
                    else
                        colour, life = { r = 0.18, g = 0.14, b = 0.14 }, C.mob_hearts_seconds
                    end
                    local across = (h * 6 + col - 1 - width / 2) * px
                    game.emit_particles{
                        pos = { x = entity.pos.x + rx * across, y = top - (row - 1) * px, z = entity.pos.z + rz * across },
                        count = 1, size = px * 1.15, lifetime = life, colour = colour,
                        gravity = 0, collide = false, player = viewer,
                    }
                end
            end
        end
    end
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
    show_hearts(entity, m.kind, entity.health, math.max(left, 0), by)
    if left <= 0 then
        -- What it leaves behind, then gone.
        for _, drop in ipairs(m.kind.drops) do
            local n = between(drop[2], drop[3] or drop[2])
            if n > 0 then
                tdl.drop({ x = entity.pos.x, y = entity.pos.y + 0.5, z = entity.pos.z },
                    { material = I.defs[game.mod_id .. ":" .. drop[1]].material, units = n * 27 },
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

--- A wander point around home, on the ground or in the air.
local function pick_wander(m, entity)
    local kind = m.kind
    local r = kind.wander_radius or 8
    local x = m.home.x + between(-r, r)
    local z = m.home.z + between(-r, r)
    local y = entity.pos.y
    if kind.flyer then
        y = m.home.y + between(kind.fly_low or 3, kind.fly_high or 9)
    end
    m.target = { x = x, y = y, z = z }
end

--- Walks a walker toward a point, facing where it goes and animating from
--- what the body did last tick. Returns false once it has arrived, or has
--- given up.
---
--- It drives the body itself rather than through `game.steer_entity`, which
--- jumps at any block with floor in it: on smooth ground that is every
--- third-of-a-block rise, which the physics climbs anyway, so animals hopped
--- across every slope. Here a walker jumps only when it is STUCK, trying to
--- walk and not moving, which is a hole or a full block in the way. If a
--- few jumps do not free it, it gives up and picks somewhere else to go.
local function walk_to(id, m, entity, target, gait)
    local dx, dz = target.x - entity.pos.x, target.z - entity.pos.z
    local flat = dx * dx + dz * dz
    if flat <= C.mob_arrival * C.mob_arrival then
        m.stuck, m.hops = 0, 0
        return false
    end
    local speed2 = entity.velocity.x * entity.velocity.x + entity.velocity.z * entity.velocity.z
    if speed2 >= C.mob_moving_speed2 or not entity.on_ground then
        if speed2 >= C.mob_moving_speed2 then m.hops = 0 end
        m.stuck = 0
    else
        m.stuck = (m.stuck or 0) + 1
    end
    local jump = false
    if m.stuck >= C.mob_stuck_ticks then
        m.stuck = 0
        m.hops = (m.hops or 0) + 1
        if m.hops > C.mob_stuck_hops then
            m.hops = 0
            return false
        end
        jump = true
    end
    local length = math.sqrt(flat)
    local ux, uz = dx / length, dz / length
    local anim = ANIM_IDLE
    if speed2 >= 0.0025 then anim = gait == "sprint" and ANIM_RUN or ANIM_WALK end
    local spec = { yaw = game.heading(dx, dz), anim = anim }

    -- A kind's own speed, in blocks a second. The engine gives a mob a
    -- player's gaits and nothing else (engine ask 14), so a kind that names
    -- its speeds drives nothing and sets its horizontal velocity instead: the
    -- speed it wants times a gain, the gain nudged each tick by what the body
    -- actually did last tick. It settles on the speed asked for, on any
    -- ground, with no knowledge of the engine's friction; the physics still
    -- collides it, steps it up a lip, and makes it fall.
    local own = gait == "sprint" and m.kind.run_speed or m.kind.walk_speed
    if own then
        local want = own * 3 / 20      -- cells a tick
        local seen = math.sqrt(speed2)
        m.gain = m.gain or 1.5
        if entity.on_ground and seen > 0.01 and m.driving then
            m.gain = U.clamp(m.gain * U.clamp(want / seen, 0.9, 1.1), 1, 4)
        end
        m.driving = true
        spec.velocity = { x = ux * want * m.gain, y = entity.velocity.y, z = uz * want * m.gain }
        spec.drive = { walk = { x = 0, z = 0 }, jump = jump }
    else
        spec.drive = { walk = { x = ux, z = uz }, jump = jump, gait = gait }
    end
    game.set_entity(id, spec)
    return true
end

--- Flies a flyer toward a point: velocity set every tick, lift added to
--- cancel the tick of gravity the physics is about to apply, and a rise
--- when the way ahead is solid.
local function fly_to(id, entity, target, speed)
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
        anim = ANIM_RUN,
    })
    return flat > 1.0 or math.abs(dy) > 1.5
end

local function move_to(id, m, entity, target, fast)
    local kind = m.kind
    if kind.flyer then
        return fly_to(id, entity, target, fast and (kind.speed_fast or 0.5) or (kind.speed or 0.3))
    end
    return walk_to(id, m, entity, target, fast and "sprint" or "walk")
end

local function stand(id, m)
    m.driving = false
    if not m.kind.flyer then
        local anim = (m.grazing and m.state == "idle") and ANIM_SNEAK or ANIM_IDLE
        -- A blow just struck: its swing clip, for as long as the swing lasts.
        if (m.swing or 0) > 0 then
            m.swing = m.swing - 1
            anim = ANIM_SWING
        end
        game.set_entity(id, { drive = { walk = { x = 0, z = 0 } }, anim = anim })
    end
end

--- Away from a threat: a point on the far side of the body from it.
local function away_from(entity, from, flyer)
    local dx, dz = entity.pos.x - from.x, entity.pos.z - from.z
    return { x = entity.pos.x + dx * 2, y = entity.pos.y + (flyer and 3 or 0), z = entity.pos.z + dz * 2 }
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
        elseif kind.shy and m.seen.d2 < kind.shy * kind.shy then
            m.state, m.threat, m.timer = "flee", m.seen.uuid, C.mob_flee_ticks // 2
        end
    end

    if m.state == "flee" then
        local from = U.body(m.threat)
        if from and m.timer > 0 then
            move_to(id, m, entity, away_from(entity, from.pos, kind.flyer), true)
        else
            m.state, m.threat, m.timer = "idle", nil, between(20, 60)
            stand(id, m)
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
    -- to lead itself.
    if kind.flock and m.flock and m.flock ~= id then
        local leader = game.entity(m.flock)
        if leader and not leader.item then
            local lm = M.live[m.flock]
            local at = { x = leader.pos.x + m.offset.x, y = leader.pos.y + m.offset.y, z = leader.pos.z + m.offset.z }
            if lm and lm.state == "hunt" and hunts_now(kind, entity) and m.seen then
                m.state, m.threat, m.timer = "hunt", lm.threat, C.mob_hunt_ticks
            elseif U.dist2(at, entity.pos) > 2 then
                move_to(id, m, entity, at, false)
            else
                stand(id, m)
            end
            return
        else
            m.flock = nil
        end
    end

    if m.state == "idle" then
        if m.timer <= 0 then
            m.state = "wander"
            m.timer = between(60, 200)
            pick_wander(m, entity)
        elseif kind.flyer then
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
            if kind.flyer then pick_wander(m, entity) end
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
    --- The nearest mob as the server sees it: what it is doing, which clip it
    --- is told to play, and how fast it is going. For checking in play.
    local ANIM_NAMES = { [0] = "idle", "walk", "run", "swing", "swim", "sneak" }
    tdl.command("mob", "admin", function(uuid)
        local body = U.body(uuid)
        local id = body and tdl.mobs_near(body.pos, C.mob_count_radius)[1]
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
