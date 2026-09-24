-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Status effects: what they are called, how often they act, and what they do
-- when they act. Applying and clearing them is `tdl.effects.*`; the vitals
-- tick drives them.
--
-- Every effect on a player is `v.fx[id] = { left = ticks, acc = ticks }`,
-- where `acc` counts up to the effect's period. `tdl.damage` and `tdl.heal`
-- exist by the time any of these run; they are defined in vitals.lua.

local C = tdl.config

local E = { defs = {}, order = {}, count = 0 }

local function effect(id, def)
    def.id = id
    E.defs[id] = def
    E.order[#E.order + 1] = id
    E.count = E.count + 1
end

-- Harmful, in the order the HUD lists them.
effect("burning", {
    name = "Burning", harmful = true, period = 10,
    act = function(uuid) tdl.damage(uuid, 1, "fire", { quiet = true }) end,
})
effect("poison", {
    name = "Poisoned", harmful = true, period = 25,
    -- The classic rule: poison brings you to your last heart and no further.
    act = function(uuid) tdl.damage(uuid, 1, "poison", { quiet = true, floor = 1 }) end,
})
effect("wither", {
    name = "Withering", harmful = true, period = 40,
    act = function(uuid) tdl.damage(uuid, 1, "wither", { quiet = true }) end,
})
effect("radiation", {
    name = "Irradiated", harmful = true, period = 30,
    act = function(uuid)
        tdl.damage(uuid, 1, "radiation", { quiet = true, floor = 1 })
        tdl.exhaust(uuid, 0.2)
    end,
})

-- Helpful.
effect("regeneration", {
    name = "Regenerating", period = 25,
    act = function(uuid) tdl.heal(uuid, 1) end,
})
effect("resistance", { name = "Resistant", damage_scale = 0.5 })
effect("warmth", { name = "Warmed", temperature = C.temp_food })
effect("cooling", { name = "Cooled", temperature = -C.temp_food })
effect("well_fed", { name = "Well fed" })
effect("rested", { name = "Well rested" })

--- Puts an effect on a player, or extends one already there to the longer
--- of the two durations. `v` is the player's vitals record.
function E.apply(v, id, ticks)
    assert(E.defs[id], "no such effect: " .. tostring(id))
    local current = v.fx[id]
    if current then
        if ticks > current.left then current.left = ticks end
    else
        v.fx[id] = { left = ticks, acc = 0 }
    end
end

function E.remove(v, id)
    v.fx[id] = nil
end

function E.has(v, id)
    return v.fx[id] ~= nil
end

--- Removes every harmful effect: the antidote, or a good night's sleep.
function E.clear_harmful(v)
    for id, def in pairs(E.defs) do
        if def.harmful then v.fx[id] = nil end
    end
end

--- Advances every effect on a player by `dt` ticks, acting when a period
--- comes round. Called from the vitals tick.
function E.tick(uuid, v, dt)
    for id, state in pairs(v.fx) do
        local def = E.defs[id]
        state.left = state.left - dt
        if def.period then
            state.acc = state.acc + dt
            while state.acc >= def.period do
                state.acc = state.acc - def.period
                if def.act then def.act(uuid) end
            end
        end
        if state.left <= 0 then
            v.fx[id] = nil
        end
    end
end

--- The multiplier active effects put on damage of a kind.
function E.damage_scale(v, kind)
    local scale = 1.0
    for id in pairs(v.fx) do
        local def = E.defs[id]
        if def.damage_scale and (kind == "physical" or kind == "explosion" or kind == "fall") then
            scale = scale * def.damage_scale
        end
    end
    return scale
end

--- What active effects add to the ambient temperature.
function E.temperature(v)
    local shift = 0
    for id in pairs(v.fx) do
        local def = E.defs[id]
        if def.temperature then shift = shift + def.temperature end
    end
    return shift
end

--- The effects on a player as one short string for the HUD: ids, harmful
--- first, in registration order. The HUD knows the names.
function E.hud_string(v)
    local list = {}
    for _, id in ipairs(E.order) do
        if v.fx[id] and E.defs[id].harmful then list[#list + 1] = id end
    end
    for _, id in ipairs(E.order) do
        if v.fx[id] and not E.defs[id].harmful then list[#list + 1] = id end
    end
    return table.concat(list, ",")
end

--- Encodes the effects for storage, and back.
function E.encode(v)
    local parts = {}
    for _, id in ipairs(E.order) do
        local state = v.fx[id]
        if state then parts[#parts + 1] = id .. ":" .. math.floor(state.left) end
    end
    return table.concat(parts, ",")
end

function E.decode(v, text)
    v.fx = {}
    if type(text) ~= "string" then return end
    for id, left in string.gmatch(text, "([%w_]+):(%d+)") do
        if E.defs[id] then
            v.fx[id] = { left = tonumber(left), acc = 0 }
        end
    end
end

return E
