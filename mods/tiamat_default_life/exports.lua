-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- What other mods may call: the table `game.exports("tiamat_default_life")`
-- answers to a mod that lists this one in `depends` or `optional_depends`.
--
-- Two readers today. Tiamat Weather (its docs/exports-contract.md) loads
-- after this mod, so it cannot be named back; it calls the fire functions
-- once at its load to put its burning block into this mod's tables. Tiamat
-- Default Craft (its docs/sibling-asks.md) will register what it cooks and
-- forges through `add_food` and `add_weapon`, and its bronze and iron farm
-- tools through `add_tilling_tool` and `add_harvest_tool`, so that what a
-- food or a tool DOES stays written here once.
--
-- # Every function here runs in THIS mod's sandbox
--
-- An error in one would disable this mod because another passed it the wrong
-- thing, so none of them raise: they check what they are given and answer
-- `false` for anything else.
--
-- Bump `version` when a change would break a reader, and only then.

local I = tdl.items
local U = tdl.util

local function block_name(name)
    return type(name) == "string" and #name <= 128 and string.match(name, "^[%w_]+:[%w_]+$") ~= nil
end

local function short_name(name)
    return type(name) == "string" and #name <= 64 and string.match(name, "^[%w_]+$") ~= nil
end

--- A whole number in lo..hi as an integer, or nil. `20` and `20.0` alike.
local function whole(n, lo, hi)
    local i = type(n) == "number" and math.tointeger(n) or nil
    if i and i >= lo and i <= hi then return i end
    return nil
end

--- A number in lo..hi, or nil.
local function real(n, lo, hi)
    if type(n) ~= "number" or n ~= n or n < lo or n > hi then return nil end
    return n
end

--- Another mod's material, by name, resolved now (its registration is done
--- by the time it can call us) — or nil.
local function material_of(name)
    if not block_name(name) then return nil end
    return U.material(name)
end

return {
    version = 1,

    --- Standing in `material` burns: `spec = { damage, ticks, after }` is a
    --- hit of `damage` points every `ticks` ticks, and `after` ticks of
    --- burning once out of it. Answers whether it was taken.
    add_contact_fire = function(material, spec)
        if not block_name(material) or type(spec) ~= "table" then return false end
        local damage, ticks, after = whole(spec.damage, 1, 27), whole(spec.ticks, 1, 1200), whole(spec.after, 0, 1200)
        if not (damage and ticks and after) then return false end
        I.add_contact_fire(material, { damage = damage, ticks = ticks, after = after })
        return true
    end,

    --- Sets `target` on fire for `ticks` (at most a minute): a player's UUID,
    --- or the entity id of one of this mod's creatures. Burning is a point
    --- every half second until it runs out or they reach water. Answers
    --- whether there was anyone to set alight: lightning, say, beside them.
    set_alight = function(target, ticks)
        local t = whole(ticks, 1, 1200)
        if not t then return false end
        if type(target) == "string" then
            if not string.match(target, "^%x+$") then return false end
        elseif math.type(target) ~= "integer" then
            return false
        end
        return tdl.set_alight(target, t) == true
    end,

    --- `material` warms whoever stands near it, `strength` from 0 to 1, as
    --- the campfire does at 1. Answers whether it was taken.
    add_heat_source = function(material, strength)
        if not block_name(material) or type(strength) ~= "number" or strength ~= strength
            or strength < 0 or strength > 1 then
            return false
        end
        I.add_heat_source(material, strength)
        return true
    end,

    --- Your item `material` is food: `spec = { food, saturation, heal,
    --- effects = { { id, ticks } }, cures = { id }, well_fed, temperature =
    --- "warm"|"cool", sound }`, the fields this mod's own foods have (items.lua).
    --- Eating it — X, or the right mouse — does what the spec says. Answers
    --- whether it was taken: the material must exist, and the effects be ours.
    add_food = function(material, spec)
        local id = material_of(material)
        if id == nil or type(spec) ~= "table" then return false end
        local def = { kind = "food", food = whole(spec.food, 0, 27) or 0, saturation = whole(spec.saturation, 0, 27) or 0,
                      heal = spec.heal ~= nil and whole(spec.heal, 1, 27) or nil, effects = {}, cures = {},
                      well_fed = spec.well_fed == true, sound = spec.sound == "drink" and "drink" or "eat" }
        if spec.temperature == "warm" or spec.temperature == "cool" then def.temperature = spec.temperature end
        for _, fx in ipairs(type(spec.effects) == "table" and spec.effects or {}) do
            local ticks = type(fx) == "table" and whole(fx[2], 1, 20 * 60 * 30)
            if not (ticks and tdl.effects.defs[fx[1]]) then return false end
            def.effects[#def.effects + 1] = { fx[1], ticks }
        end
        for _, cure in ipairs(type(spec.cures) == "table" and spec.cures or {}) do
            if not tdl.effects.defs[cure] then return false end
            def.cures[#def.cures + 1] = cure
        end
        I.add_def(material, id, def)
        return true
    end,

    --- Your item `material` is a weapon: a punch with it in hand does `damage`
    --- points (a fist does one, the reference sword six).
    add_weapon = function(material, damage)
        local id = material_of(material)
        local d = whole(damage, 1, 100)
        if id == nil or d == nil then return false end
        I.weapons[id] = d
        return true
    end,

    --- One of this mod's creatures (`kind`, its short id: "cow") also leaves
    --- `min` to `max` of your item `material` when it dies.
    add_drop = function(kind, material, min, max)
        local def = short_name(kind) and tdl.mobs.kinds[kind]
        local lo, hi = whole(min, 0, 64), whole(max, 0, 64)
        if not def or not block_name(material) or not lo or not hi or hi < lo then return false end
        def.drops[#def.drops + 1] = { material, lo, hi, qualified = true }
        return true
    end,

    --- Your item `material` is feed for these kinds (short ids): a fed
    --- animal is ready to breed.
    add_feed = function(material, kinds)
        local id = material_of(material)
        if id == nil or type(kinds) ~= "table" then return false end
        local list = {}
        for _, kind in ipairs(kinds) do
            if not (short_name(kind) and tdl.mobs.kinds[kind]) then return false end
            list[#list + 1] = kind
        end
        tdl.husbandry.add_feed(id, list)
        return true
    end,

    --- A crop of yours, grown and harvested by this mod's rules: `def` as
    --- `tdl.register_crop` takes it (farming.lua), except that `stages` is a
    --- list of the qualified ids of YOUR stage blocks, registered by you (a
    --- texture is a file of the mod that registers the block), sprouting
    --- first and ripe last, and `seed` and `produce` are qualified ids of
    --- your items. Do not random-tick those blocks yourself: this mod does,
    --- and the engine allows one handler per material. Registration window
    --- only; answers whether it was taken.
    add_crop = function(def)
        if type(def) ~= "table" or not short_name(def.id) or type(def.stages) ~= "table" then return false end
        local n = #def.stages
        if n < 2 or n > 8 then return false end
        for _, id in ipairs(def.stages) do
            if not block_name(id) or U.material(id) == nil then return false end
        end
        if not (block_name(def.seed) and block_name(def.produce)) then return false end
        if def.soil ~= "tilled" and def.soil ~= "wet" and type(def.soil) ~= "table" then return false end
        if U.material(def.seed) == nil or U.material(def.produce) == nil then return false end
        local ok, crop = pcall(tdl.register_crop, {
            id = def.id, name = type(def.name) == "string" and def.name or nil, stages = n, stage_ids_given = def.stages,
            seed = def.seed, produce = def.produce, qualified = true,
            produce_min = whole(def.produce_min, 0, 64) or 1, produce_max = whole(def.produce_max, 0, 64) or 1,
            seed_min = whole(def.seed_min, 0, 64) or 1, seed_max = whole(def.seed_max, 0, 64) or 1,
            soil = def.soil, light = def.light == "dark" and "dark" or "sun",
            biomes = type(def.biomes) == "table" and def.biomes or nil,
        })
        if not ok then return false end
        tdl.farming.tick_crop(crop)
        return true
    end,

    --- Your tool `material` harvests: a ripe crop dug with it gives `yield`
    --- times what a hand gives (this mod's sickle gives two).
    add_harvest_tool = function(material, yield)
        local id = material_of(material)
        local y = real(yield, 1, 8)
        if id == nil or y == nil then return false end
        tdl.farming.add_harvest_tool(id, y)
        return true
    end,

    --- Your tool `material` tills: grass or earth right-clicked with it is
    --- tilled ground.
    add_tilling_tool = function(material)
        local id = material_of(material)
        if id == nil then return false end
        tdl.farming.add_tilling_tool(id)
        return true
    end,

    --- Puts a stack on the ground, looked after by this mod (picked up by
    --- whoever walks over it, gone after five minutes): `stack = { material,
    --- units | count, shape, detail }`, `opts = { velocity, owner }`. Answers
    --- the entity id, or nil.
    drop = function(pos, stack, opts)
        if type(pos) ~= "table" or type(stack) ~= "table" then return nil end
        local x, y, z = real(pos.x, -1e7, 1e7), real(pos.y, -1e7, 1e7), real(pos.z, -1e7, 1e7)
        local material = material_of(stack.material) or (math.type(stack.material) == "integer" and stack.material)
        if not (x and y and z and material) then return nil end
        local units = whole(stack.units, 1, 27 * 90) or (whole(stack.count, 1, 90) or 0) * 27
        if units <= 0 then return nil end
        local o = type(opts) == "table" and opts or {}
        return tdl.drop({ x = x, y = y, z = z },
            { material = material, units = units, shape = whole(stack.shape, 1, 0x7FFFFFF), detail = type(stack.detail) == "string" and stack.detail or nil },
            { velocity = type(o.velocity) == "table" and o.velocity or nil, owner = type(o.owner) == "string" and o.owner or nil })
    end,
}
