-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Stats another mod keeps on a player through this one: mana, charge,
-- whatever a path needs a bar for. This mod holds the number, fills it
-- back at the rate asked, saves it with the vitals, and draws it on its
-- own HUD beside hunger, so a magic mod does not ship a second HUD.
--
--   tdl.add_stat(id, spec)           spec = { max, regen, name, colour, start }
--   tdl.stats.get(uuid, id)          the value, or nil
--   tdl.stats.set(uuid, id, value)   clamped to 0..max
--   tdl.stats.spend(uuid, id, amount)   true and taken, or false and untouched
--   tdl.stats.set_max(uuid, id, max)    this player's own ceiling, or nil for the stat's;
--                                       a stat at a ceiling of 0 is not drawn for them
--
-- `regen` is points a tick (a twentieth of a second); a stat starts at
-- `start`, or full. Ids are the ADDING mod's names, qualified by it
-- ("tiamat_magic:mana"), and the HUD shows `name`.

local C = tdl.config
local U = tdl.util

local M = { defs = {}, order = {} }
tdl.stats = M

function tdl.add_stat(id, spec)
    assert(M.defs[id] == nil, "stat added twice: " .. id)
    local def = {
        id = id,
        max = spec.max,
        regen = spec.regen or 0,
        name = spec.name or U.friendly(id),
        colour = spec.colour or { 120, 160, 255 },
        start = spec.start or spec.max,
    }
    M.defs[id] = def
    M.order[#M.order + 1] = id
    -- Players already here get it now; the rest as they arrive.
    for _, v in pairs(tdl.online()) do
        v.stats = v.stats or {}
        if v.stats[id] == nil then v.stats[id] = def.start end
    end
    return def
end

--- A player's ceiling for a stat: their own if one was set, else the stat's.
local function max_of(v, id)
    local own = v.stat_max and v.stat_max[id]
    if own then return own end
    return M.defs[id].max
end
M.max_of = max_of

--- Sets a player's own ceiling for a stat (nil: back to the stat's), and
--- brings the value under it.
function M.set_max(uuid, id, max)
    local v = tdl.get(uuid)
    if v == nil or M.defs[id] == nil then return false end
    v.stat_max = v.stat_max or {}
    v.stat_max[id] = max
    v.stats = v.stats or {}
    if v.stats[id] and v.stats[id] > max_of(v, id) then v.stats[id] = max_of(v, id) end
    return true
end

--- The player's value of a stat, or nil for no such stat or player.
function M.get(uuid, id)
    local v = tdl.get(uuid)
    local def = M.defs[id]
    if v == nil or def == nil then return nil end
    v.stats = v.stats or {}
    if v.stats[id] == nil then v.stats[id] = math.min(def.start, max_of(v, id)) end
    return v.stats[id]
end

function M.set(uuid, id, value)
    if M.get(uuid, id) == nil then return false end
    local v = tdl.get(uuid)
    v.stats[id] = U.clamp(value, 0, max_of(v, id))
    return true
end

--- Takes `amount` off a stat if there is that much; else leaves it be.
function M.spend(uuid, id, amount)
    local have = M.get(uuid, id)
    if have == nil or have < amount then return false end
    tdl.get(uuid).stats[id] = have - amount
    return true
end

--- The stats as one string for storage: "id=value,...", and back.
function M.encode(v)
    local parts = {}
    for _, id in ipairs(M.order) do
        local value = v.stats and v.stats[id]
        if value then parts[#parts + 1] = id .. "=" .. string.format("%.3f", value) end
    end
    return table.concat(parts, ",")
end

function M.decode(v, text)
    v.stats = v.stats or {}
    if type(text) ~= "string" then return end
    for id, value in string.gmatch(text, "([%w_:]+)=([%d%.]+)") do
        if M.defs[id] then v.stats[id] = U.clamp(tonumber(value) or 0, 0, max_of(v, id)) end
    end
end

--- The player's own ceilings, for storage: "id=max,...", and back.
function M.encode_max(v)
    local parts = {}
    for _, id in ipairs(M.order) do
        local own = v.stat_max and v.stat_max[id]
        if own then parts[#parts + 1] = id .. "=" .. string.format("%.3f", own) end
    end
    return table.concat(parts, ",")
end

function M.decode_max(v, text)
    v.stat_max = v.stat_max or {}
    if type(text) ~= "string" then return end
    for id, value in string.gmatch(text, "([%w_:]+)=([%d%.]+)") do
        if M.defs[id] then v.stat_max[id] = tonumber(value) end
    end
end

--- What the HUD is told: which bars to draw, and each one's value. Bars
--- are numbered in the order drawn (a HUD value's name is at most 32
--- bytes, which a qualified id is not): the list is "Name:r,g,b;..." and
--- the values `stat1`, `stat1_max`, `stat2`, ... A stat whose ceiling is 0
--- for this player is not drawn for them.
function M.hud(v, values)
    if #M.order == 0 then return end
    local list = {}
    v.stats = v.stats or {}
    local n = 0
    for _, id in ipairs(M.order) do
        local def = M.defs[id]
        local max = max_of(v, id)
        if v.stats[id] == nil then v.stats[id] = math.min(def.start, max) end
        if max > 0 then
            n = n + 1
            list[#list + 1] = def.name .. ":" .. def.colour[1] .. "," .. def.colour[2] .. "," .. def.colour[3]
            values["stat" .. n] = U.round(v.stats[id] * 10) / 10
            values["stat" .. n .. "_max"] = max
        end
    end
    values.stats = table.concat(list, ";")
end

-- Filling back, a tick at a time.
tdl.on_tick(function(dt)
    if #M.order == 0 then return end
    for _, v in pairs(tdl.online()) do
        if not v.dead then
            v.stats = v.stats or {}
            for _, id in ipairs(M.order) do
                local def = M.defs[id]
                local value = v.stats[id]
                local max = max_of(v, id)
                if value == nil then
                    v.stats[id] = math.min(def.start, max)
                elseif def.regen > 0 and value < max then
                    v.stats[id] = math.min(max, value + def.regen * dt)
                end
            end
        end
    end
end)

return M
