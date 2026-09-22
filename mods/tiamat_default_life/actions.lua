-- SPDX-License-Identifier: GPL-3.0-only
--
-- What a player can DO about their vitals: eat, take medicine, dress, sleep.
-- Plus the explosion API for whatever blows up later, foraging from the
-- world's brambles, and the chat words that make all of it testable.

local C = tdl.config
local U = tdl.util
local E = tdl.effects
local I = tdl.items

local USE = game.mod_id .. ":use"
local WARDROBE = game.mod_id .. ":wardrobe"
local USE_COOLDOWN = 15
local FOOD_TEMPERATURE_TICKS = 20 * 60   -- a minute of warmth or coolness from a meal

local use_cd = {}       -- uuid -> tick the next use is allowed
local wardrobe_open = {}

-- Eating and medicine ---------------------------------------------------------

local function consume(uuid, v, held, def)
    if def.kind == "food" and v.food >= C.max_food and not def.heal then
        tdl.toast(uuid, "You are full.")
        return
    end
    if def.needs_injury and v.hp >= C.max_health then
        tdl.toast(uuid, "You are not hurt.")
        return
    end
    if def.needs_affliction then
        local afflicted = false
        for _, id in ipairs(def.cures) do
            if E.has(v, id) then afflicted = true end
        end
        if not afflicted then
            tdl.toast(uuid, "Nothing to cure.")
            return
        end
    end

    local took = game.take(uuid, { material = held.material, count = 1, shape = held.shape, detail = held.detail })
    if took <= 0 then return end

    if def.food then tdl.feed(uuid, def.food, def.saturation) end
    if def.heal then tdl.heal(uuid, def.heal) end
    for _, fx in ipairs(def.effects or {}) do
        E.apply(v, fx[1], fx[2])
    end
    for _, id in ipairs(def.cures or {}) do
        E.remove(v, id)
    end
    if def.temperature == "warm" then
        E.remove(v, "cooling")
        E.apply(v, "warmth", FOOD_TEMPERATURE_TICKS)
    elseif def.temperature == "cool" then
        E.remove(v, "warmth")
        E.apply(v, "cooling", FOOD_TEMPERATURE_TICKS)
    end
    if def.well_fed then
        E.apply(v, "well_fed", C.well_fed_ticks)
    end
    tdl.cue(uuid, def.sound or "eat")
    if def.kind == "food" then
        tdl.toast(uuid, "You ate " .. string.lower(def.name) .. ".", 40)
    else
        tdl.toast(uuid, "You used " .. string.lower(def.name) .. ".", 40)
    end
end

-- Sleep -------------------------------------------------------------------------

--- A bed within reach of the feet, or nil.
local function bed_near(pos)
    local feet = U.block_at(pos)
    local reach = C.bed_reach
    for dy = -1, 1 do
        for dx = -reach, reach do
            for dz = -reach, reach do
                local at = { x = feet.x + dx, y = feet.y + dy, z = feet.z + dz }
                local block = game.get_block(at)
                if block and block.material == I.bed and block.occupancy ~= 0 then
                    return at
                end
            end
        end
    end
    return nil
end

local function is_night()
    local t = game.time_of_day()
    return t < C.night_before or t > C.night_after
end

--- The one thing that keeps you up: being hurt right now. Nothing about
--- what is prowling nearby, by design: a bed is a bed.
local function unsafe_reason(uuid, v)
    if tdl.now - v.last_damage < 100 then
        return "You cannot sleep while you are being hurt."
    end
    return nil
end

--- Whether every living player here has slept lately: the night ends then.
local function everyone_slept()
    for other, w in pairs(tdl.online()) do
        if not (w.dead or tdl.is_ghost(other)) then
            if w.slept_at == nil or tdl.now - w.slept_at > C.sleep_window then return false end
        end
    end
    return true
end

local function sleep(uuid, v, bed)
    tdl.set_bed(uuid, bed)
    if not (is_night() or C.sleep_any_time) then
        tdl.toast(uuid, "You can only sleep at night. This bed is now home.", 80)
        return
    end
    local reason = unsafe_reason(uuid, v)
    if reason then
        tdl.toast(uuid, reason, 80)
        return
    end
    -- A full night's rest: everything back, everything bad gone.
    v.hp = C.max_health
    v.air = C.max_air
    v.temp = 0
    E.clear_harmful(v)
    E.apply(v, "rested", C.rested_ticks)
    v.slept_at = tdl.now
    tdl.cue(uuid, "rested")
    if everyone_slept() and game.set_time_of_day(C.wake_time) then
        for other in pairs(tdl.online()) do
            tdl.toast(other, other == uuid and "You slept well, and it is morning. This bed is home."
                or "Everyone slept. It is morning.", 100)
        end
        return
    end
    tdl.toast(uuid, "You slept well. This bed is home. The night ends when everyone sleeps.", 100)
end

-- The use key ---------------------------------------------------------------------

tdl.on_action(USE, function(event)
    if not event.pressed then return end
    local uuid = event.player
    local v = tdl.get(uuid)
    if v == nil or v.dead then return end
    if tdl.is_ghost(uuid) then
        tdl.toast(uuid, "You died in this world. You can only watch.", 80)
        return
    end
    if (use_cd[uuid] or 0) > tdl.now then return end
    use_cd[uuid] = tdl.now + USE_COOLDOWN

    local held = game.held(uuid)
    local def = held and I.by_material[held.material]
    if def and (def.kind == "food" or def.kind == "medicine") then
        consume(uuid, v, held, def)
        return
    end
    if def and def.kind == "clothing" then
        tdl.toast(uuid, "Wear it: open the wardrobe and put it in a worn slot.")
        return
    end

    -- The bed being aimed at, or else one within reach of the feet.
    local at = game.looking_at(uuid)
    local bed = at and at.material == I.bed and { x = at.x // 3, y = at.y // 3, z = at.z // 3 }
    if bed == nil then
        local body = U.body(uuid)
        bed = body and bed_near(body.pos)
    end
    if bed then
        sleep(uuid, v, bed)
        return
    end
    tdl.toast(uuid, "Nothing to use. Hold food, or look at a bed.")
end)

-- Using a bed with the place control: the same as X beside it, aimed. The
-- engine calls this only with an empty hand or an unplaceable item held, so
-- a player carrying blocks still builds against a bed.
tdl.on_use(function(event)
    if event.material ~= I.bed then return end
    local v = tdl.get(event.player)
    if v == nil or v.dead then return end
    sleep(event.player, v, { x = event.x // 3, y = event.y // 3, z = event.z // 3 })
    return ""
end)

-- The wardrobe --------------------------------------------------------------------

local function wardrobe_screen()
    return {
        type = "container", direction = "column", gap = 8, padding = 12,
        children = {
            { type = "label", text = "Worn", style = { text_size = 22 } },
            { type = "label", text = "Clothing here keeps you warm, or cool. Two layers is plenty.",
              style = { text_size = 15, text_colour = { 170, 170, 170 } } },
            { type = "item_grid", view = I.worn_view, columns = 4, first = 1, count = 4 },
            { type = "spacer", size = 8 },
            { type = "label", text = "Carried", style = { text_size = 22 } },
            { type = "item_grid", view = "player:main", columns = 9, first = 1, count = 27 },
        },
    }
end

tdl.on_action(WARDROBE, function(event)
    if not event.pressed then return end
    local uuid = event.player
    if wardrobe_open[uuid] then
        game.close_dialog{ player = uuid, form = "wardrobe" }
        wardrobe_open[uuid] = nil
    else
        game.show_dialog{ player = uuid, form = "wardrobe", tree = wardrobe_screen() }
        wardrobe_open[uuid] = true
    end
end)

tdl.on_dialog("wardrobe", function(event)
    if event.kind == "closed" then
        wardrobe_open[event.player] = nil
    end
end)

tdl.on_leave(function(event)
    wardrobe_open[event.player] = nil
    use_cd[event.player] = nil
end)

-- Foraging: digging a bramble also yields berries ---------------------------------

tdl.on_dig_complete(function(event)
    local forage = I.forage[event.material]
    if forage then
        game.give(event.player, { material = game.mod_id .. ":" .. forage.item, count = forage.count })
    end
end)

-- Explosions ------------------------------------------------------------------------

--- Blows something up: `{ pos, radius, damage, blocks }`. Every player in
--- the radius is hurt and shoved in proportion to how close they stood;
--- with `blocks = true` (radius up to 4) the ground goes too.
function tdl.explode(spec)
    local pos, radius = spec.pos, spec.radius or 3
    local r2 = radius * radius
    game.cue{ cue = "boom", pos = pos, radius = 64 }
    for uuid, v in pairs(tdl.online()) do
        if v.pos then
            local centre = { x = v.pos.x, y = v.pos.y + 0.9, z = v.pos.z }
            local d2 = U.dist2(centre, pos)
            if d2 < r2 then
                local d = math.sqrt(d2)
                local factor = 1 - d / radius
                local push
                if d > 0.01 then
                    local scale = C.explosion_push * factor / d
                    push = {
                        x = (centre.x - pos.x) * scale,
                        y = C.explosion_push_up * factor + (centre.y - pos.y) * scale * 0.5,
                        z = (centre.z - pos.z) * scale,
                    }
                else
                    push = { x = 0, y = C.explosion_push_up, z = 0 }
                end
                tdl.damage(uuid, (spec.damage or 12) * factor, "explosion", { push = push })
            end
        end
    end
    if spec.blocks and radius <= 4 then
        local c = U.block_at(pos)
        local r = math.floor(radius)
        for dx = -r, r do
            for dy = -r, r do
                for dz = -r, r do
                    if dx * dx + dy * dy + dz * dz <= r2 then
                        game.set_block({ x = c.x + dx, y = c.y + dy, z = c.z + dz }, "engine:air")
                    end
                end
            end
        end
    end
end

-- Chat words, for testing -----------------------------------------------------------

if C.dev_commands then
    local function kit(uuid)
        for _, def in pairs(I.defs) do
            game.give(uuid, { material = def.id, count = def.kind == "clothing" and 1 or 4 })
        end
        game.give(uuid, { material = game.mod_id .. ":bed", count = 2 })
        game.give(uuid, { material = game.mod_id .. ":campfire", count = 4 })
        tdl.say(uuid, "A kit: every food, medicine and garment, two beds, four campfires.")
    end

    tdl.command("kit", "creative", kit)

    tdl.command("vitals", "anyone", function(uuid)
        local v = tdl.get(uuid)
        if v == nil then return end
        local line = string.format(
            "hp %d/%d  food %d/%d (visible %d)  air %d/%d  temp %.2f (ambient %.2f, heat %.2f, cold %.2f, clothing %d)  fx [%s]  submerged %s wet %s fire %s  deaths %d",
            v.hp, C.max_health, v.food, C.max_food, C.visible_food, v.air, C.max_air,
            v.temp, v.env.ambient, v.env.heat or 0, v.env.cold or 0, v.warmth,
            E.hud_string(v), tostring(v.env.submerged), tostring(v.env.wet), tostring(v.env.fire ~= nil), v.deaths)
        game.log("tiamat_default_life vitals " .. tdl.name(uuid) .. ": " .. line)
        tdl.say(uuid, string.format("hp %d food %d air %d temp %.2f", v.hp, v.food, v.air, v.temp))
    end)

    tdl.command("hurt", "admin", function(uuid, rest)
        tdl.damage(uuid, tonumber(rest) or 5, "physical", { cause = "were hurt on purpose" })
    end)
    tdl.command("heal", "admin", function(uuid)
        tdl.heal(uuid, C.max_health)
    end)
    tdl.command("feed", "admin", function(uuid)
        tdl.feed(uuid, C.max_food)
    end)
    tdl.command("starve", "admin", function(uuid, rest)
        local v = tdl.get(uuid)
        if v then v.food = tonumber(rest) or 0 end
    end)
    tdl.command("poison", "admin", function(uuid, rest)
        local v = tdl.get(uuid)
        if v then E.apply(v, "poison", tonumber(rest) or 200) end
    end)
    tdl.command("wither", "admin", function(uuid, rest)
        local v = tdl.get(uuid)
        if v then E.apply(v, "wither", tonumber(rest) or 200) end
    end)
    tdl.command("burn", "admin", function(uuid, rest)
        local v = tdl.get(uuid)
        if v then E.apply(v, "burning", tonumber(rest) or 100) end
    end)
    tdl.command("choke", "admin", function(uuid)
        local v = tdl.get(uuid)
        if v then v.air = 3 end
    end)
    tdl.command("freeze", "admin", function(uuid)
        local v = tdl.get(uuid)
        if v then v.temp = -0.95 end
    end)
    tdl.command("roast", "admin", function(uuid)
        local v = tdl.get(uuid)
        if v then v.temp = 0.95 end
    end)
    tdl.command("boom", "admin", function(uuid, rest)
        local body = U.body(uuid)
        if body then
            tdl.explode{ pos = { x = body.pos.x + 2, y = body.pos.y + 1, z = body.pos.z },
                radius = tonumber(rest) or 3, damage = 12 }
        end
    end)
    tdl.command("die", "admin", function(uuid)
        tdl.damage(uuid, 999, "physical", { force = true, cause = "gave up" })
    end)
end

return {}
