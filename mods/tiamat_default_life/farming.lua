-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The farm: tilled ground, what grows on it, and what is found in the wild
-- to start it with.
--
--   tdl.register_crop(def)       a crop; see crops.lua for the fields
--   tdl.farming.trample(pos)     a body landed here: tilled ground under it is trodden flat
--   tdl.farming.plant(uuid, crop, at)   sows a crop on the block at `at`, if it may go there
--   tdl.farming.harvest(uuid, block, material)   what a dig of a crop hands over
--
-- # How growth works, and why it is a random tick
--
-- A crop is a run of BLOCKS, one per stage (`wheat_1`, `wheat_2`, `wheat_3`):
-- the engine keeps nothing per block but its material, so a stage is a
-- material. The engine's random tick offers each loaded block a turn now and
-- then (rarely, on purpose: that is what makes a crop take a while), and a
-- stage that gets a turn advances when the ground under it is tilled and
-- wet, the light is right, and a roll of the dice allows — on dry ground a
-- third as often, and outside the crop's own biomes a third as often again.
-- Integer counters and one deterministic stream (util.lua): the same field
-- ticked the same way ripens the same way on every machine.
--
-- Only this mod's own blocks are ticked. The engine allows one handler per
-- material across every mod, and the world mod ticks its own grass and
-- snow, so a bramble's berries grow back on a block of OURS
-- (`bramble_picked`) that turns back into the world's bramble, and an apple
-- is found in an apple leaf when it is broken rather than grown on it.
--
-- # Water
--
-- Tilled ground declares `absorbs` (items.lua), so a fluid touching it —
-- the river it is dug beside, a puddle of rain, a bucket poured — turns it
-- wet through the engine, with no code here. What the engine has no answer
-- for is drying: a random tick of ours dries wet ground with no water within
-- `farmland_water_reach`, and wets dry ground that has some. Rain reaches
-- the field through the same mechanism, so this mod never asks Weather
-- anything (it could not: Weather loads after it).

local C = tdl.config
local U = tdl.util
local I = tdl.items

local M = { crops = {}, order = {}, by_stage = {}, by_seed = {}, harvest_tools = {}, tilling_tools = {} }
tdl.farming = M

local W = "tiamat_default_world:"
local AIR = "engine:air"

-- Edits a hook may not make on the spot (a dig that is still being decided)
-- are made on the next tick.
local later = {}
local function next_tick(fn)
    later[#later + 1] = fn
end

--- Whether a block is empty.
local function is_air(pos)
    local block = game.get_block(pos)
    return block ~= nil and block.occupancy == 0
end

--- The block a use event is aimed at, or nil for a use at nothing.
local function aimed_block(event)
    if event.x == nil then return nil end
    return U.cell_block(event.x, event.y, event.z)
end

-- Tilled ground ----------------------------------------------------------------------

--- The blocks a hoe turns: the world's turf and bare earth.
local TILLABLE = U.materials({ [W .. "grass"] = true, [W .. "dirt"] = true, [W .. "packed_dirt"] = true })
local DIRT = U.material(W .. "dirt")
-- The world's water, as a fluid: what a bucket scoops, and pours. Its
-- number is the fluid's, not its block's (`game.fluid_id`), and it is
-- handed out once every mod has loaded, so it is asked for on first use
-- rather than here.
local WATER = nil
local function water_fluid()
    if WATER == nil and game.fluid_id then WATER = game.fluid_id(W .. "water") end
    return WATER
end

-- Tell the world our ground is its dirt, so its own rules (which soil owns a
-- grass block, what the HUD calls the ground) read it as ground rather than
-- as a foreign block.
do
    local world = game.exports and game.exports("tiamat_default_world")
    if world and type(world.add_soil_alias) == "function" then
        world.add_soil_alias(game.mod_id .. ":farmland", W .. "dirt")
        world.add_soil_alias(game.mod_id .. ":wet_farmland", W .. "dirt")
    end
end

--- Whether there is water within reach of a block of tilled ground: the
--- blocks around it at its own level and one down, which is where a pond
--- dug beside a field sits.
local function water_near(pos)
    local r = C.farmland_water_reach
    for dy = 0, -1, -1 do
        for dx = -r, r do
            for dz = -r, r do
                if game.get_fluid({ x = pos.x + dx, y = pos.y + dy, z = pos.z + dz }).volume > 0 then
                    return true
                end
            end
        end
    end
    return false
end

--- Tills the block at `at` with a hoe: turf or earth, with air over it.
local function till(uuid, at)
    local block = game.get_block(at)
    if block == nil or not TILLABLE[block.material] or block.cells then return false end
    if not is_air({ x = at.x, y = at.y + 1, z = at.z }) then return false end
    game.set_block(at, game.mod_id .. (water_near(at) and ":wet_farmland" or ":farmland"))
    tdl.cue(uuid, "thud", 0.4)
    return true
end

--- A body landed on `pos`: tilled ground under its feet is trodden back to
--- earth, and a crop standing there is flattened. Called by the vitals
--- (environment.lua) for players and by the creatures (mobs.lua) for
--- themselves, on the one tick the engine says they landed.
function M.trample(pos)
    local feet = U.block_at(pos)
    local under = { x = feet.x, y = feet.y - 1, z = feet.z }
    local block = game.get_block(under)
    if block and (block.material == I.farmland or block.material == I.wet_farmland) then
        if DIRT then game.set_block(under, W .. "dirt") end
        if M.by_stage[(game.get_block(feet) or {}).material] then
            game.set_block(feet, AIR)
        end
    end
end

-- Crops -----------------------------------------------------------------------------------

--- Registers a crop. `def`:
---   id           the crop; its stage blocks are `<id>_1` .. `<id>_<stages>`,
---                drawn from `textures/<id>_<n>.png` — or, for another mod's crop
---                (exports.lua's `add_crop`), `stage_ids_given` is a list of ITS
---                block ids, already registered, which this mod then grows and harvests
---   stages       how many, 2 or more; the last is ripe
---   seed         the item sown, and given back at harvest (an item id of this mod's,
---                or a qualified one when `qualified` is set)
---   produce      the item a ripe one gives, `produce_min` to `produce_max` of it
---   seed_min, seed_max   seeds a ripe one gives back (an unripe one gives one)
---   soil         "tilled" (dry or wet tilled ground), "wet" (wet only), or a
---                list of the world's block ids it grows on (a mushroom's floor)
---   light        "sun": needs `crop_light` of sun; "dark": needs less than `mushroom_light`
---   biomes       where it belongs; elsewhere it grows `crop_out_of_place_scale` times slower
---   name         what the stage blocks are called
function tdl.register_crop(def)
    assert(def.id and def.stages and def.seed and def.produce, "a crop needs an id, stages, a seed and produce")
    def.stage_ids = {}
    def.stage_materials = {}
    def.biome_set = {}
    for _, biome in ipairs(def.biomes or {}) do def.biome_set[biome] = true end
    if type(def.soil) == "table" then
        local set = {}
        for _, id in ipairs(def.soil) do set[id] = true end
        def.soil_set = U.materials(set)
    end
    for n = 1, def.stages do
        local id = def.id .. "_" .. n
        local ripe = n == def.stages
        local material = def.stage_ids_given and U.material(def.stage_ids_given[n]) or game.register_block{
            id = id,
            name = (def.name or U.friendly(def.id)) .. (ripe and " (ripe)" or n == 1 and " (sprouting)" or " (growing)"),
            description = ripe and "Ready to harvest. A sickle takes twice as much." or "Growing. Keep the ground wet.",
            hardness = 0.1,
            textures = { all = "textures/" .. id .. ".png" },
            billboard = "cross", passable = true, sway = true, washes_away = true,
            -- Nothing by the engine's rule: what a dig of a crop hands over is
            -- decided here, by stage and by tool (`M.harvest`).
            drops = {},
        }
        assert(material, "a crop's stage block must be registered: " .. tostring(def.stage_ids_given and def.stage_ids_given[n]))
        def.stage_ids[n] = def.stage_ids_given and def.stage_ids_given[n] or game.mod_id .. ":" .. id
        def.stage_materials[n] = material
        M.by_stage[material] = { crop = def, stage = n }
    end
    -- What a harvest hands over, as `game.give` names it; and the seed in a
    -- hand, which is how a crop is found when it is sown.
    def.seed_id = def.qualified and def.seed or game.mod_id .. ":" .. def.seed
    def.produce_id = def.qualified and def.produce or game.mod_id .. ":" .. def.produce
    local seed = U.material(def.seed_id)
    assert(seed, "a crop's seed must be a registered item: " .. def.seed_id)
    M.by_seed[seed] = def
    M.crops[def.id] = def
    M.order[#M.order + 1] = def.id
    return def
end

--- Whether the ground under a crop is right for it: `soil` as registered.
--- Answers the soil's wetness too: "wet", "dry", or nil for the wrong ground.
local function soil_under(def, pos)
    local under = game.get_block({ x = pos.x, y = pos.y - 1, z = pos.z })
    if under == nil or under.occupancy == 0 then return nil end
    if def.soil_set then
        return def.soil_set[under.material] and "wet" or nil
    end
    if under.material == I.wet_farmland then return "wet" end
    if under.material == I.farmland and def.soil ~= "wet" then return "dry" end
    return nil
end

--- Whether the light at a spot suits a crop.
local function light_suits(def, pos)
    local sun = game.get_light(pos).sun
    if def.light == "dark" then return sun < C.mushroom_light end
    return sun >= C.crop_light
end

--- One turn for a stage block: advance, if everything allows.
local function grow(def, stage, event)
    local pos = { x = event.x, y = event.y, z = event.z }
    local wet = soil_under(def, pos)
    if wet == nil or not light_suits(def, pos) then return end
    local chance = wet == "wet" and C.crop_grow_chance or C.crop_grow_dry_chance
    if next(def.biome_set) ~= nil then
        local biome = tdl.mobs.biome_at(pos)
        if biome and not def.biome_set[biome] then chance = chance // C.crop_out_of_place_scale end
    end
    if U.chance(chance) then
        game.set_block(pos, def.stage_ids[stage + 1])
    end
end

--- Sows `crop` so it stands on the block at `at`. Answers whether it did,
--- and a reason when it did not.
function M.plant(uuid, crop, at)
    local def = M.crops[crop]
    if def == nil then return false end
    local above = { x = at.x, y = at.y + 1, z = at.z }
    if soil_under(def, above) == nil then
        return false, def.soil == "wet" and "It wants wet tilled ground."
            or def.soil_set and "It wants the floor of a cave." or "It wants tilled ground."
    end
    if not is_air(above) then return false, "Something is in the way." end
    game.set_block(above, def.stage_ids[1])
    tdl.cue(uuid, "thud", 0.3)
    return true
end

--- A dig of a crop block: seeds back, and produce if it was ripe, twice as
--- much with a harvest tool. The block itself drops nothing (its `drops`).
function M.harvest(uuid, entry)
    local def, stage = entry.crop, entry.stage
    local held = game.held(uuid)
    local tool = held and M.harvest_tools[held.material] or 1
    local seeds = 1
    if stage == def.stages then
        local n = U.between(def.produce_min or 1, def.produce_max or 1) * tool
        game.give(uuid, { material = def.produce_id, count = n })
        seeds = U.between(def.seed_min or 1, def.seed_max or 1)
    end
    game.give(uuid, { material = def.seed_id, count = seeds })
end

-- Foraging ----------------------------------------------------------------------------
--
-- Digging one of the world's plants leaves something in the bag besides the
-- plant: berries from a bramble, and the first seed of every crop, from the
-- wild plant that stands for it (config.lua's `forage`, by chance).
local function forage(uuid, material)
    local list = I.forage[material]
    if list == nil then return end
    for _, entry in ipairs(list) do
        if entry[3] == nil or U.chance(entry[3]) then
            game.give(uuid, { material = game.mod_id .. ":" .. entry[1], count = entry[2] or 1 })
        end
    end
end

-- Brambles ---------------------------------------------------------------------------
--
-- The world's bramble, right-clicked, gives its berries without being dug,
-- and stands picked bare (our block) until they grow back.
local BRAMBLE = U.material(W .. "bramble")

if game.register_random_tick then
    game.register_random_tick(I.bramble_picked, function(event)
        if BRAMBLE and U.chance(C.bramble_regrow_chance) then
            game.set_block({ x = event.x, y = event.y, z = event.z }, W .. "bramble")
        end
    end)
end

-- Hooks -------------------------------------------------------------------------------

tdl.on_dig_complete(function(event)
    -- Nothing here refuses a dig; it only decides what goes in the bag, and
    -- what falls with the ground.
    local entry = M.by_stage[event.material]
    if entry then
        M.harvest(event.player, entry)
        return
    end
    forage(event.player, event.material)
    if event.material == I.farmland or event.material == I.wet_farmland then
        -- The ground dug out from under a crop: the crop goes with it,
        -- giving its seed back, a tick on when the ground has gone.
        local at = U.cell_block(event.x, event.y, event.z)
        local above = { x = at.x, y = at.y + 1, z = at.z }
        local standing = M.by_stage[(game.get_block(above) or {}).material]
        if standing then
            local player = event.player
            next_tick(function()
                game.set_block(above, AIR)
                game.give(player, { material = standing.crop.seed_id, count = 1 })
            end)
        end
    end
end)

tdl.on_use(function(event)
    local uuid = event.player
    local v = tdl.get(uuid)
    if v == nil or v.dead then return end
    local held = event.held
    local def = held and I.by_material[held.material]
    local at = aimed_block(event)

    -- Sowing: a seed, at ground it may go in.
    local crop = held and M.by_seed[held.material]
    if crop and at then
        local planted, why = M.plant(uuid, crop.id, at)
        if planted then
            game.take(uuid, { material = held.material, count = 1 })
            return ""
        end
        return why or ""
    end
    if def and def.kind == "seed" and def.crop == "bramble" and at then
        local block = game.get_block(at)
        local above = { x = at.x, y = at.y + 1, z = at.z }
        if BRAMBLE and block and TILLABLE[block.material] and is_air(above) then
            game.take(uuid, { material = held.material, count = 1 })
            game.set_block(above, W .. "bramble")
            return ""
        end
        return "Plant it on grass or dirt."
    end

    -- Tilling.
    if held and M.tilling_tools[held.material] and at then
        if till(uuid, at) then return "" end
        return "Till grass or bare earth, with nothing on it."
    end

    -- A bucket: water from the world, and water onto the field.
    if def and def.bucket == true and at then
        local water = water_fluid()
        if water == nil then return nil end
        local top = game.surface_at{ x = at.x, z = at.z, from = at.y, depth = 0 }
        local there = game.get_fluid(at)
        if top and top.fluid == water and top.y == at.y and there.volume >= 9 then
            game.take(uuid, { material = held.material, count = 1 })
            game.set_fluid(at, { fluid = W .. "water", volume = 0 })
            game.give(uuid, { material = game.mod_id .. ":water_bucket", count = 1 })
            tdl.cue(uuid, "drink")
            return ""
        end
        return nil
    end
    if def and def.bucket == "water" and at then
        local block = game.get_block(at)
        if block and (block.material == I.farmland or block.material == I.wet_farmland) then
            -- Watering: the block and its neighbours.
            for dx = -1, 1 do
                for dz = -1, 1 do
                    local p = { x = at.x + dx, y = at.y, z = at.z + dz }
                    local b = game.get_block(p)
                    if b and b.material == I.farmland then game.set_block(p, game.mod_id .. ":wet_farmland") end
                end
            end
        else
            -- Pouring: a block of water where the click landed, against the face.
            if water_fluid() == nil then return "There is no water in this world to pour." end
            local look = game.looking_at(uuid)
            local into = look and { x = at.x + look.face.x, y = at.y + look.face.y, z = at.z + look.face.z } or nil
            if into == nil or not is_air(into) then return "Nowhere to pour it." end
            game.set_fluid(into, { fluid = W .. "water", volume = 27 })
        end
        game.take(uuid, { material = held.material, count = 1 })
        game.give(uuid, { material = game.mod_id .. ":bucket", count = 1 })
        tdl.cue(uuid, "drink")
        return ""
    end

    -- Picking a bramble bare-handed.
    if at and event.material == BRAMBLE and (held == nil or def == nil or def.kind ~= "tool") then
        forage(uuid, BRAMBLE)
        game.set_block(at, game.mod_id .. ":bramble_picked")
        tdl.cue(uuid, "eat")
        return ""
    end
end)

-- The ground's own turns.
if game.register_random_tick then
    game.register_random_tick(I.farmland, function(event)
        local pos = { x = event.x, y = event.y, z = event.z }
        if water_near(pos) then
            game.set_block(pos, game.mod_id .. ":wet_farmland")
        elseif DIRT and is_air({ x = pos.x, y = pos.y + 1, z = pos.z }) and U.chance(C.farmland_revert_chance) then
            game.set_block(pos, W .. "dirt")
        end
    end)
    game.register_random_tick(I.wet_farmland, function(event)
        local pos = { x = event.x, y = event.y, z = event.z }
        if not water_near(pos) and U.chance(C.farmland_dry_chance) then
            game.set_block(pos, game.mod_id .. ":farmland")
        end
    end)
end

--- Registers the random tick of every crop's stages. Called once, after
--- crops.lua, since a crop another mod adds through the exports arrives
--- in the registration window too and is ticked the same way.
function M.tick_crop(def)
    if not game.register_random_tick then return end
    for n = 1, def.stages - 1 do
        game.register_random_tick(def.stage_materials[n], function(event)
            grow(def, n, event)
        end)
    end
end

--- A tool that harvests: `yield` times a hand's.
function M.add_harvest_tool(material, yield)
    M.harvest_tools[material] = yield
end

--- A tool that tills.
function M.add_tilling_tool(material)
    M.tilling_tools[material] = true
end

for material, def in pairs(I.by_material) do
    if def.harvest then M.add_harvest_tool(material, def.harvest) end
    if def.tills then M.add_tilling_tool(material) end
end

tdl.on_tick(function()
    if #later == 0 then return end
    local batch = later
    later = {}
    for _, fn in ipairs(batch) do fn() end
end)

return M
