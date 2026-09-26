-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Husbandry: what a player does WITH an animal rather than to it. Feeding
-- and breeding, milk, wool, eggs and honey, leading one on a rope, and the
-- gate of the pen it lives in.
--
--   tdl.husbandry.step(id, m, entity, dt)   one tick of an animal's domestic life; true if it took the tick
--   tdl.husbandry.add_feed(material, kinds) another mod's food, for these kinds
--
-- Everything here starts from the place control on a creature
-- (`tdl.on_use_entity`, engine ask 17): the server casts the ray, so the
-- cow you milk is the cow you are looking at. A kind says what it eats
-- (`feeds`), whether it `breeds`, and what it gives (`milk`, `wool`,
-- `lays`) in creatures.lua; the numbers are config.lua's.
--
-- What is remembered across a restart: that a young one is young (its
-- model), and that a pair is expecting (storage, by the mother's entity id,
-- as the creatures remember a grudge). That an animal was fed a moment ago,
-- or milked, is not: those are a few minutes long, and a world that closes
-- forgets them, which errs on the side of the player.

local C = tdl.config
local U = tdl.util
local I = tdl.items
local MOBS = tdl.mobs

local M = { feeds = {} }
tdl.husbandry = M

local W = "tiamat_default_world:"
local now = 0

--- What `material` is feed for: a set of kind ids, or nil.
local function feed_for(material)
    return M.feeds[material]
end

--- Whether a feed suits a kind.
local function eats(kind, held)
    if held == nil then return false end
    local kinds = feed_for(held.material)
    return kinds ~= nil and kinds[kind.id] == true
end

--- Another mod's feed: `kinds` is a list of kind ids it is for.
function M.add_feed(material, kinds)
    local set = M.feeds[material] or {}
    for _, id in ipairs(kinds) do set[id] = true end
    M.feeds[material] = set
end

-- The kinds' own feeds, from creatures.lua, by item id of this mod's.
for _, kid in ipairs(MOBS.order) do
    local kind = MOBS.kinds[kid]
    for _, item in ipairs(kind.feeds or {}) do
        local def = I.defs[game.mod_id .. ":" .. item]
        if def then M.add_feed(def.material, { kid }) end
    end
end

--- Says something to a player over the animal, briefly.
local function tell(uuid, text)
    tdl.toast(uuid, text, 40)
end

-- Using an animal ---------------------------------------------------------------------

tdl.on_use_entity(function(event)
    if event.owner ~= nil then return end
    local id = event.target
    local entity = game.entity(id)
    if entity == nil or entity.source ~= game.mod_id or entity.item then return end
    local m = MOBS.live[id] or MOBS.adopt(id, entity)
    if m == nil then return end
    local uuid = event.player
    local v = tdl.get(uuid)
    if v == nil or v.dead then return end
    local kind = m.kind
    local held = event.held
    local def = held and I.by_material[held.material]

    -- A lead: on, or off again.
    if def and def.lead then
        if m.led == uuid then
            m.led = nil
            tell(uuid, "You let the " .. string.lower(kind.name) .. " go.")
        elseif m.led then
            return "Somebody else is leading it."
        elseif kind.flyer or kind.hostile or kind.still then
            return "It will not be led."
        else
            m.led = uuid
            m.state, m.threat, m.target = "idle", nil, nil
            tell(uuid, "You lead the " .. string.lower(kind.name) .. ".")
        end
        return ""
    end

    -- Feeding: a fed adult is ready to breed for a while.
    if eats(kind, held) then
        if m.young then
            return "It is too young."
        end
        if (m.fed_until or 0) > now then
            return "It has had enough."
        end
        game.take(uuid, { material = held.material, count = 1 })
        m.fed_until = now + C.fed_ticks
        game.cue{ cue = "eat", pos = entity.pos, radius = 16, entity = id }
        tell(uuid, "The " .. string.lower(kind.name) .. " eats.")
        return ""
    end

    -- Milk, into a bucket.
    if def and def.bucket == true and kind.milk then
        if m.young then return "It is too young." end
        if (m.milked_until or 0) > now then return "Nothing yet. Give it a while." end
        game.take(uuid, { material = held.material, count = 1 })
        game.give(uuid, { material = game.mod_id .. ":milk", count = 1 })
        m.milked_until = now + C.milk_ticks
        tdl.cue(uuid, "drink")
        return ""
    end

    -- Wool, with shears.
    if def and def.shears and kind.wool then
        if m.young then return "It is too young." end
        if (m.shorn_until or 0) > now then return "Shorn already. It grows back." end
        game.give(uuid, { material = game.mod_id .. ":wool", count = U.between(1, 3) })
        m.shorn_until = now + C.wool_ticks
        tdl.cue(uuid, "eat")
        return ""
    end

    -- An empty hand, or the wrong thing: say what it is, and let the click go.
    if held == nil then
        tell(uuid, "A " .. string.lower(kind.name) .. (m.young and ", young." or "."))
        return ""
    end
    return nil
end)

-- The animal's own tick ---------------------------------------------------------------

--- Puts a young one of `kind` beside `pos`.
local function bear(kind, pos)
    local ids = tdl.spawn_mob(kind.id, { x = pos.x + 1, y = pos.y, z = pos.z }, 1, { young = true })
    return ids[1]
end

--- A young one, grown: the same animal in its adult body, where it stood.
local function grow_up(id, m, entity)
    local kind, pos = m.kind, entity.pos
    game.despawn_entity(id)
    MOBS.live[id] = nil
    tdl.spawn_mob(kind.id, { x = pos.x, y = pos.y, z = pos.z }, 1)
end

--- Looks for a fed partner of the same kind near a fed animal, and makes
--- the pair expect. Called on the perceive cadence.
local function court(id, m, entity)
    for _, other in ipairs(tdl.mobs_near(entity.pos, C.breed_reach)) do
        local om = other ~= id and MOBS.live[other]
        if om and om.kind == m.kind and not om.young and (om.fed_until or 0) > now
            and om.breed_in == nil and (om.bred_until or 0) <= now then
            m.fed_until, om.fed_until = nil, nil
            m.breed_in = C.breed_ticks
            om.bred_until = now + C.breed_cooldown_ticks
            game.storage.set("breed:" .. id, m.breed_in)
            return
        end
    end
end

--- One tick of an animal's domestic life. Answers true when it has taken
--- the tick (a led animal follows and does nothing else).
function M.step(id, m, entity, dt)
    local kind = m.kind

    -- Growing up.
    if m.young then
        m.grow_left = (m.grow_left or C.grow_up_ticks) - dt
        if m.grow_left <= 0 then
            grow_up(id, m, entity)
            return true
        end
    end

    -- Expecting, and then a birth.
    if m.breed_in then
        m.breed_in = m.breed_in - dt
        if m.breed_in <= 0 then
            m.breed_in = nil
            m.bred_until = now + C.breed_cooldown_ticks
            game.storage.set("breed:" .. id, nil)
            bear(kind, entity.pos)
        elseif (now + m.perceive_at) % 100 == 0 then
            game.storage.set("breed:" .. id, m.breed_in)
        end
    elseif kind.breeds and not m.young and (m.fed_until or 0) > now and (m.bred_until or 0) <= now
        and (now + m.perceive_at) % 10 == 0 then
        court(id, m, entity)
    end

    -- Laying.
    if kind.lays and not m.young then
        m.lay_in = (m.lay_in or U.between(C.egg_ticks_min, C.egg_ticks_max)) - dt
        if m.lay_in <= 0 then
            m.lay_in = U.between(C.egg_ticks_min, C.egg_ticks_max)
            tdl.drop({ x = entity.pos.x, y = entity.pos.y + 0.3, z = entity.pos.z },
                { material = I.defs[game.mod_id .. ":egg"].material, units = 27 })
        end
    end

    -- On a lead: it follows whoever holds the rope, and the rope comes off
    -- if they get too far ahead or leave.
    if m.led then
        local holder = U.body(m.led)
        local d2 = holder and U.dist2(holder.pos, entity.pos)
        if holder == nil or d2 > U.square(C.lead_break) then
            m.led = nil
            return false
        end
        if d2 > U.square(C.lead_reach) then
            MOBS.move_to(id, m, entity, holder.pos, d2 > U.square(C.lead_reach * 2.5))
        else
            MOBS.stand(id, m)
        end
        return true
    end
    return false
end

--- What a record needs when an animal is first seen this session.
function M.adopt(id, m, entity)
    if entity.model and string.find(entity.model, "_young$") then m.young = true end
    if entity.nametag and string.find(entity.nametag, "%(young%)$") then m.young = true end
    if m.young then m.grow_left = C.grow_up_ticks end
    local expecting = game.storage.get("breed:" .. id)
    if math.type(expecting) == "integer" and expecting > 0 then m.breed_in = expecting end
end

--- The animal is gone: what was kept for it goes too.
function M.forget(id, m)
    if m.breed_in then game.storage.set("breed:" .. id, nil) end
end

-- Gates -------------------------------------------------------------------------------

tdl.on_use(function(event)
    if event.x == nil then return end
    local at = U.cell_block(event.x, event.y, event.z)
    if event.material == I.gate then
        game.set_block(at, game.mod_id .. ":gate_open")
        return ""
    elseif event.material == I.gate_open then
        game.set_block(at, game.mod_id .. ":gate")
        return ""
    end
end)

-- Hives ---------------------------------------------------------------------------------
--
-- A hive fills by random tick when there are flowers near it, and a full
-- one is emptied of its honey with a right-click. Wild hives are found
-- under the trees of the flower forest: a spawn pass of the same cadence
-- as the creatures', never more than `hive_per_chunk` in a chunk column,
-- remembered with the world so a forest does not fill with them.

local FLOWERS = U.materials((function()
    local set = {}
    for _, id in ipairs(C.flowers) do set[id] = true end
    return set
end)())

local function flowers_near(pos)
    local r = C.hive_flower_reach
    for dy = -2, 1 do
        for dx = -r, r do
            for dz = -r, r do
                if U.material_in(FLOWERS, { x = pos.x + dx, y = pos.y + dy, z = pos.z + dz }) then return true end
            end
        end
    end
    return false
end

if game.register_random_tick then
    game.register_random_tick(I.beehive, function(event)
        local pos = { x = event.x, y = event.y, z = event.z }
        if U.chance(C.hive_fill_chance) and flowers_near(pos) then
            game.set_block(pos, game.mod_id .. ":beehive_full")
        end
    end)
end

tdl.on_use(function(event)
    if event.x == nil or event.material ~= I.beehive_full then return end
    local at = U.cell_block(event.x, event.y, event.z)
    game.give(event.player, { material = game.mod_id .. ":honey", count = U.chance(30) and 2 or 1 })
    game.set_block(at, game.mod_id .. ":beehive")
    tdl.cue(event.player, "drink")
    return ""
end)

--- One look for a wild hive near a player: a column at random in reach,
--- in the flower forest, whose top is a tree; the hive goes on the first
--- clear block under the canopy.
local function find_hive(v)
    local pos = v.pos
    if pos == nil or not U.chance(100 // C.hive_chance) then return end
    local dist = U.between(C.mob_spawn_min, C.mob_spawn_max)
    local dx = U.between(-dist, dist)
    local dz = (U.below(2) == 0 and 1 or -1) * (dist - math.abs(dx))
    local x, z = math.floor(pos.x) + dx, math.floor(pos.z) + dz
    local key = "hive:" .. (x // 16) .. "," .. (z // 16)
    if (game.storage.get(key) or 0) >= C.hive_per_chunk then return end
    local top = game.surface_at{ x = x, z = z, from = math.floor(pos.y) + 32, depth = 96 }
    if top == nil or not I.perches[top.material] then return end
    local biome = MOBS.biome_at({ x = x, y = top.y, z = z })
    if biome ~= "flower_forest" then return end
    for y = top.y - 1, top.y - 12, -1 do
        local block = game.get_block({ x = x, y = y, z = z })
        if block == nil then return end
        if block.occupancy == 0 then
            game.set_block({ x = x, y = y, z = z }, game.mod_id .. ":beehive")
            game.storage.set(key, (game.storage.get(key) or 0) + 1)
            game.log(string.format("tiamat_default_life: a wild hive at %d, %d, %d", x, y, z))
            return
        end
    end
end

local spawn_acc = 0

tdl.on_tick(function(dt)
    now = now + dt
    spawn_acc = spawn_acc + dt
    if spawn_acc < C.mob_spawn_every then return end
    spawn_acc = 0
    for _, v in pairs(tdl.online()) do
        find_hive(v)
    end
end)

return M
